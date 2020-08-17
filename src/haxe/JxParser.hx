package mxd;

import hxd.Math;
import mxd.tools.ColorTools;
using StringTools;

/**
 * EqParser parses mathematical (and other) equations from a string.
 * 		Mathematical pperators: + - / * ^ % ( )
 * 		String operators: +
 * 		Constants: PI, PI_2, INV_PI
 * 		Mathematical functions:
 * 			min, max, floor, ceil, round
 * 			cos, sin, tan, acos, asin, atan, atan2
 * 			sqrt, pow
 * 			abs, clamp, lerp
 * 			degToRad, radToDeg
 * 			random
 * 		Color functions:
 * 			red, green, blue, alpha
 * 			opacity, darken, lighten, tint
 * 
 * Usage:
 * 		p = new EqParser();
 * 		trace( p.parse("12.81 - sin( PI * 0.25 )") );
 * 		trace( p.parse("darken( #9722da, 0.2)") );
 * 		trace( p.parse("round( 12 + random(20) )") );
 * 		
 * 		p = new EqParser();
 * 		p.onVariable = function( var : String ) : Dynamic {
 * 			if (var == 'myName') return 'Equation Parser';
 * 			else return null;
 * 		}
 * 		trace( p.parse("'hello, ' + $myName + '. How are you?'") );
 * 
 * 		p = new EqParser();
 * 		function myFunc( a : Float, b : Int ) : Float {
 * 			return (a*2) % b;
 * 		}
 * 		p.onFunction = function( fnc : String, args : Array<Dynamic> ) : Dynamic {
 * 			if (fnc == 'myFunc') return myFunc( args[0], args[1] );
 * 			else return null;
 * 		}
 * 		trace( p.parse( "12 * myFunc( 22.12, 3 )") );
 * 
 * Algorithm based on description here: https://stackoverflow.com/a/47717/6036640
 */

/**
 * Indicates the type of token parsed from the expression string
 */
enum TokenType {
	TTUnknown;
	TTOpenBracket;
	TTCloseBracket;
	TTArrayStart;
	TTArrayEnd;
	TTObjectStart;
	TTObjectEnd;
	TTOperator( t:Int );
	TTArray;
	TTObject;
	TTString;
	TTNumber;
	TTVariable;
	TTDefaultVariable;
	TTLook;
	TTFunction;
	TTSeperator;
	TTAssignment;
	TTEndOfFile;
}

/**
 * For functions, indicates the required type for each argument
 */
enum ArgType {
	ATNumber;	// Either Int and Float
	ATInt;
	ATString;
}

/**
 * A token is one individual part of an expression.It could be a number,
 * a math operator, a function name, etc.
 */
class Token {
	public var pos : Int;
	public var type : TokenType = TTUnknown;
	public var closingType : TokenType = TTUnknown;
	public var rawValue : StringBuf = new StringBuf();
	public var value(default,set) : Dynamic;
	public var args : Array<Token>;

	/**
	 * Constructor
	 * @param t 	The token type
	 */
	public function new( t : TokenType = TTUnknown ){
		type = t;
	}

	/**
	 * Set the actual value of the token (based on parsing rawValue, usually) and
	 * try to determine it's actual type.
	 * @param v 		The value
	 * @return Dynamic	The value
	 */
	function set_value( v : Dynamic ) : Dynamic {
		value = v;
		if ( Std.is(v, std.Array) ) type = TTArray;
		else if ( Std.is(v, std.String) ) type = TTString;
		else if ( Type.typeof(v) == TObject ) type = TTObject;
		else if ( Math.isNaN( v ) ) type = TTUnknown;
		else if ( Std.is(v, StdTypes.Float) ) type = TTNumber;
		else if ( Std.is(v, StdTypes.Int) ) type = TTNumber;
		else type = TTUnknown;
		return v;
	}

	/**
	 * Check that the arguments stored on this token are of the correct type
	 * @param types 	The expected argument types
	 */
	public function checkArgs( types : Array<ArgType> ) {
		if (args.length != types.length) return false;
		for (i in 0...args.length){
			switch (types[i]) {
				case ATInt:
					if (!Std.is( args[i].value, Int )) return false;
				case ATNumber:
					if (!Std.is( args[i].value, Float ) && !Std.is( args[i].value, Int )) return false;	
				case ATString:
					if (!Std.is( args[i].value, String )) return false; 
			}
		}
		return true;
	}

	/**
	 * Reverse the sign of the value
	 */
	public function negate() : Token {
		value = -value;
		return this;
	}

	/**
	 * Trace this token
	 */
	public function trace( tab : Int = 0 ) {
		var s = '';
		for (i in 0...tab) s += ' ';
		trace(s+'token.pos: '+this.pos);
		trace(s+'token.rawValue: '+this.rawValue);
		trace(s+'token.value: '+this.value);
		switch (this.type) {
			case TTOperator(t): trace(s+'token.type: TTOperator('+String.fromCharCode(t)+')');
			default: trace(s+'token.type: '+this.type);
		}
		switch (this.closingType) {
			case TTOperator(t): trace(s+'token.closingType: TTOperator('+String.fromCharCode(t)+')');
			default: trace(s+'token.closingType: '+this.type);
		}
	}
}

/**
 * The stack for storing and processing values and operators
 */
class Stack {
	var last : TokenType = TTUnknown;
	var stack : Array<Token> = new Array();
	public var nested(default,null) : Int = 0;
	public function new() {}

	/**
	 * Check if stack is empty
	 */
	public function isEmpty() : Bool {
		return stack.length==0;
	}

	/**
	 * Add a token to the stack. Checks for correct token order.
	 * @param v 	The token to push
	 */
	public function push( token : Token ) {
		// Check if allowed to push token
		switch (token.type) {
			// Pushing an operator
			case TTOperator(o): {
				switch (last) {
					// An operator can only follow a value
					case TTOperator(_), TTOpenBracket, TTUnknown: unexpected( token );
					// Push the operator
					default: {
						// If no other operators, always push
						if (stack.length<2) {
							stack.push( token );
						}
						// Otherwise prcoess stack until a lower token is found
						else {
							while ( (stack.length>1) && lowerOrSame( token ) ) process( 1 );
							stack.push( token );
						}
					}
				}
			}
			// An open bracket cannot follow a value
			// A negative number can follow a value because it is likely a subtraction (e.g. 17 -8)
			default: {
				switch (last) {
					case TTOperator(_), TTOpenBracket, TTArray, TTObject, TTUnknown: {
						// if bracket, increase nesting counter
						if (token.type == TTOpenBracket) nested++;
						// Push token
						stack.push( token );
					}
					default: 
						if (token.value < 0) {
							push( new Token( TTOperator('-'.code) ) );
							stack.push( token.negate() );
						}
						else unexpected( token );
				}
			}
		}
		// Remember last
		last = token.type;
	}

	/**
	 * Process one or more operations from the stack
	 * @param	count		The number of operations to perform from the stack. If 0, process the whole stack
	 */
	public function process( count : Int = 0 ) : Token {
		// Need at least three tokens on the stack to process it
		while ( stack.length > 2 ) {
			var b = stack.pop();
			var op = stack.pop();
			var a = stack.pop();

			var c = new Token();
			c.type = a.type;
			switch ( op.type ) {
				case TTOperator('+'.code): {
					if (a.type == TTArray) {
						if (b.type == TTArray) {
							c.value = a.value.concat( b.value );
						}
						else {
							c.value = a.value;
							c.value.push( b.value );
						}
					}
					else if (b.type == TTArray) {
						c.value = b.value;
						c.value.unshift( a.value );
					}
					else {
						c.value = a.value + b.value;
					}
				}
				case TTOperator('-'.code): c.value = a.value - b.value;
				case TTOperator('/'.code): c.value = a.value / b.value;
				case TTOperator('*'.code): c.value = a.value * b.value;
				case TTOperator('^'.code): c.value = Math.pow( a.value, b.value );
				case TTOperator('%'.code): c.value = a.value % b.value;
				default:
					error('Unknown operator "${op.type}"',op.pos);
			}
			stack.push( c );
			count--;
			if (count==0) break;
		}
		if (stack.length == 0) return null;
		return stack[0];
	}

	/**
	 * Process stack until an opening bracket is found
	 */
	public function processToBracket() {
		// Otherwise process to opening bracket
		while (true) {
			// If next on stack is opening bracket, remove it and exit
			if ( stack[ stack.length-1 ].type == TTOpenBracket) {
				stack.pop();
				return;
			}
			// If second on stack is opening bracket, 'process' the value in between
			if ( stack[ stack.length-2 ].type == TTOpenBracket) {
				var t = stack.pop();
				stack.pop();
				stack.push( t );
				return;
			}
			// Otherwise process a single operation
			process( 1 );
			// Exit if stack is empty
			if (stack.length<2) break;
		}
	}

	/**
	 * Check if the token is lower than the one on top of the stack
	 * @param a 		The token to check
	 * @return Bool		True if token is higher than the token on the stack
	 */
	inline function lowerOrSame( a : Token ) : Bool {
		var b = stack[stack.length-2];
		return order( a ) <= order( b );
	}

	/**
	 * Return the precedence order of an operator
	 */
	function order( t : Token ) : Int {
		switch (t.type) {
			case TTOpenBracket:
				return 1;
			case TTOperator('+'.code), TTOperator('-'.code):
				return 2;
			case TTOperator('*'.code), TTOperator('/'.code):
				return 3;
			case TTOperator('^'.code), TTOperator('%'.code):
				return 4;
			default:
				error('Cannot calculate precendence. Unknown operator "${t.type}"',t.pos);
				return 0;
		}
	}

	/**
	 * Check if the last token on the stack is an operator
	 * @return Bool		True if the last token is an operator
	 */
	public function lastIsOperaor() : Bool {
		switch (last){
			case TTOperator(_): return true;
			default: return false;
		}
	}

	/**
	 * Fatal error
	 * @param msg 	The message
	 * @param pos 	The position in the equation string
	 */
	inline function unexpected( t : Token ) {
		var desc = '';
		switch (t.type){
			case TTOperator(t): desc = ' TTOperator("'+String.fromCharCode(t)+'")';
			case TTString, TTNumber, TTFunction: desc = ' "'+t.rawValue.toString()+'"';
			default: desc = ' '+t.type;
		}
		error( 'Unexpected token'+desc, t.pos );
	}
	inline function error( msg : String, pos : Int ) {
		throw msg + ' at ' + pos;
	}

	/**
	 * Trace this stack
	 */
	public function trace( tab : Int = 0 ) {
		var s = '';
		for (i in 0...tab) s += ' ';
		trace(s+'stack');
		if ( stack.length == 0 ) {
			trace(s+'  empty');
			return;
		}
		for (i in 0...stack.length) {
			trace(s+i+':');
			stack[i].trace(tab+2);
		}
	}

}

/**
 * Equation parser class. Call EqParser.parse( str : String ) to parse equations from a string. Implement
 * the onFunction, onVariable and onParameter callbacks to support custom functionallity.
 */
class JxParser {

	var str : String;
	var pos : Int;

	/**
	 * User variables
	 */
	public var variables : Map<String,Dynamic> = new Map();

	/**
	 * Callback to catch any unknown variables in the equation. (e.g. $myVariable )
	 */
	public var onVariable : String->Dynamic = null;

	/**
	 * User constants
	 */
	public var constants : Map<String,Dynamic> = new Map();

	/**
	 * Callback to catch any unknown constants in the equation. (e.g. MY_CONST )
	 */
	public var onConstant : String->Dynamic = null;

	/**
	 * Callback to catch any unknown functions in the equation. (e.g. myFunc( ) )
	 */
	public var onFunction : String->Array<Dynamic>->Dynamic = null;

	/**
	 * Constructor
	 */
	public function new() {}

	/**
	 * Start parsing an equation
	 * @param str 		The equation string
	 * @return Dynamic	The result
	 */
	public function parse( str : String ) : Dynamic {
		this.str = str;
		pos = 0;
		return parseExpr( false ).value;
	}

	/**
	 * Parse an expression. An expression is actually a full equation, but because of
	 * function calls, multiple expressions can exist in an equation. For example:
	 * 17 + 3 * 1.22 / sin( 18.11 ^ 2 - 0.399 * 4229 )
	 * 		The first expression is 17 + 3 * 1.22 / sin(...)
	 * 		A second expression is 18.11 ^ 2 - 0.399 * 4229
	 * @return Token	The last token to be processed, which contains the value and other important info
	 */
	function parseExpr( inFunc : Bool, isKey : Bool = false ) : Token {

		var stack : Stack = new Stack();
		var token : Token = null;

		while (pos < str.length) {

			// Find the next token
			token = parseToken( isKey );

			// Process the found token
			switch ( token.type ) {
				// Parse an array (values)
				case TTArrayStart: {
					var arr = [];
					var found = false;
					// Parse expressions and add to array until end of array is found
					while (pos < str.length){
						var t : Token = parseExpr( false );
						if ( t != null ) {
							arr.push( t.value );
						}
						if ( ( t == null ) || ( t.closingType == TTArrayEnd ) ){
							token.value = arr;
							stack.push( token );
							found = true;
							break;
						}
					}
					if (found) continue;
					error('Unexpected end of file after '+token.pos, pos);
				}
				// Parse an object (key/values)
				case TTObjectStart: {
					var obj = {};
					var key : Dynamic = null;
					var k : Token = null;
					var v : Token = null;
					var found = false;
					while (pos < str.length){
						// Parse expression, which is key, or end of object
						k = parseExpr( false, true );
						if ( k != null ) {
							if (k.closingType != TTAssignment) error('Colon expected',pos);
							key = k.value;
							// Get the value
							v = parseExpr( false );
							// The key is a variable...
							if ( k.type == TTVariable ) {
								variables.set( key, v.value );
							}
							// The key is a default variable...
							else if ( k.type == TTDefaultVariable ) {
								if ( !variables.exists( key ) ) variables.set( key, v.value );
							}
							// Standard key...
							else {
								Reflect.setField(obj, key, v.value);
							}
						}
						// Check if the object is closed
						if ( ( k == null ) || ( v.closingType == TTObjectEnd ) ){
							token.value = obj;
							stack.push( token );
							found = true;
							break;
						}
					}
					if (found) continue;
					error('Unexpected end of file after '+token.pos, pos);
				}
				// Function found. Parse the function and push the result to the stack
				case TTFunction: {
					parseFunction( token );
					stack.push( token );
				}
				// Seperator found. Process stack
				case TTSeperator: {
					//if (!inFunc) unexpected( token );
					token = stack.process();
					token.closingType = TTSeperator;
					return token;
				}
				// Close bracket found
				case TTCloseBracket: {
					// If there are opening brackets, process the stack to the opening bracket
					if (stack.nested > 0) {
						stack.processToBracket();
					}
					// The there are no opening brackets, should be last function argument. return it.
					else {
						if (!inFunc) unexpected( token );
						token = stack.process();
						token.closingType = TTCloseBracket;
						return token;
					}
				}
				// End of file encountered
				case TTEndOfFile, TTArrayEnd, TTObjectEnd, TTAssignment: {
					// Remember closing type
					var tt = token.type;
					// Check if in a function
					if (inFunc) error('Unexpected token',token.pos);
					// Check if last is operator
					if (stack.lastIsOperaor()) error('Unexpected token',token.pos);
					// If stack is empty, this is a trailing seperator and should be ignored
					if (stack.isEmpty()) return null;
					// Process the stack
					token = stack.process();
					token.closingType = tt;
					return token;
				}
				// Found a mathematical operator, open bracket or value
				case TTOperator(_), TTOpenBracket, TTNumber, TTString, TTVariable, TTDefaultVariable: {
					// Push to the stack
					stack.push( token );
				}
				// Something else has been found
				default: {
					unexpected( token );
				}
			}
		}

		return token;
	}

	/**
	 * Parse all arguments for a function. At this point we have the function
	 * name, and we are inside the bracket, about to parse the first argument.
	 * @param token 	The function token
	 */
	public function parseFunction( token : Token ) {
		token.args = new Array();
		var argument : Token = null;
		while (true){
			// Process the argument
			argument = parseExpr( true );
			token.args.push( argument );

			// Check expression was terminated correctly
			if ( argument.closingType == TTCloseBracket ) {
				token.value = processFunction( token );
				break;
			}
			// If not end of function, seperator is expected
			else if ( argument.closingType != TTSeperator ) {
				unexpected( token );
			}

		}
		return token;
	}

	/**
	 * Grab the next token. It could be a value, an operator, a function, etc.
	 * Comments and whitespace are ignored.
	 */
	public function parseToken( isKey : Bool = false ) : Token {
		var start = pos;
		var quote = 0;
		var started = false;
		var ended = false;
		var token : Token = new Token();

		while (pos < str.length) {
			// Get next character from input
			var c = next();

			// Have not yet started
			if (!started){
				token.pos = pos - 1;
				switch (c) {
					// Ignore whitespace
					case ' '.code, '\r'.code, '\n'.code, '\t'.code: {}
					// Comment
					case '/'.code: {
						var n = peek();
						// Line comment. Ignore until newline
						if (n == '/'.code) {
							while (pos < str.length){
								n = next();
								if ((n == '\n'.code) || (n == '\r'.code)) break;
							}
							continue;
						}
						// Block comment. Ignore until end of block comment
						if (n == '*'.code) {
							while (pos < str.length) {
								if ((next() == '/'.code) && (peek(-2) == '*'.code)) break;
							}
							continue;
						}
						// Otherwise operator
						token.type = TTOperator(c);
						break;
					}
					// Array
					case '['.code: {
						token.type = TTArrayStart;
						return token;
					}
					case ']'.code: {
						token.type = TTArrayEnd;
						return token;
					}
					// Object
					case '{'.code: {
						token.type = TTObjectStart;
						return token;
					}
					case '}'.code: {
						token.type = TTObjectEnd;
						return token;
					}
					// Start string
					case '"'.code, '\''.code: {
						token.type = TTString;
						quote = c;
						started = true;
					}
					// Operators
					case '+'.code, '*'.code, '^'.code, '%'.code: {
						token.type = TTOperator(c);
						break;
					}
					// Special case, negative number or subtract operator
					case '-'.code: {
						var cc = peek(); // Peek at next char
						if (((cc < '0'.code) || (cc > '9'.code)) && (cc != '.'.code)) {
							token.type = TTOperator(c);
							break;
						}
						token.rawValue.addChar( c );
						started = true;
					}
					// Brackets
					case '('.code: {
						token.type = TTOpenBracket;
						return token;
					}
					case ')'.code: {
						token.type = TTCloseBracket;
						return token;
					}
					// Seperator (next argument)
					case ','.code, ';'.code: {
						token.type = TTSeperator;
						return token;
					}
					// Assignment (value follows)
					case ':'.code: {
						token.type = TTAssignment;
						return token;
					}
					// Variable
					case '$'.code: {
						token.type = TTVariable;
						started = true;
					}
					// Default variable
					case '?'.code: {
						if ( peek() == '$'.code ) {
							next();
							token.type = TTDefaultVariable;
						}
						else {
							token.rawValue.addChar( c );	
						}
						started = true;
					}
					// Any other character
					default:
						token.rawValue.addChar( c );
						started = true;
				}
			}

			// Parsing string
			else if (token.type == TTString) {
				switch (c) {
					// End string
					case '"'.code, '\''.code: {
						if (quote == c) break;
						token.rawValue.addChar( c );
					}
					// Escaped character
					case '\\'.code: {
						var cc = next();
						switch (cc) {
							case "r".code:
								token.rawValue.addChar("\r".code);
							case "n".code:
								token.rawValue.addChar("\n".code);
							case "t".code:
								token.rawValue.addChar("\t".code);
							case "b".code:
								token.rawValue.addChar(8);
							case "f".code:
								token.rawValue.addChar(12);
							case 'u'.code:
								// XXX: Add unicode support (see JsonParser)
								error( 'Unicode not yet supported', pos-1 );
							default:
								token.rawValue.addChar(c); // Literally add the char
						}
					}
					// Any other character, including inline newlines, tabs and other whitespace!
					default:
						token.rawValue.addChar( c );
				}
			}

			// Variable or function
			else {
				switch (c) {
					// If terminated by bracket, is a function
					case '('.code: {
						token.type = TTFunction;
						break;
					}
					// Ends if find operator, bracket, seperator or assignment
					case '+'.code, '-'.code, '/'.code, '*'.code, '^'.code, '%'.code, ')'.code, ']'.code, '}'.code, ','.code, ';'.code, ':'.code: {
						rewind();
						break;
					}
					// Start end sequence if whitespace found
					case ' '.code, '\r'.code, '\n'.code, '\t'.code: {
						ended = true;
					}
					// Other
					default: {
						if (ended) {
							rewind();
							break;
						}
						else {
							token.rawValue.addChar( c );
						}
					}
				}
			}
			
		}
		// Check for end of file
		if (pos >= str.length) {
			token.type = TTEndOfFile;
		}
		// Token is default variable (always assignment)
		else if ( token.type == TTDefaultVariable ) {
			if (!isKey) error( "Unexpected default variable assignment", token.pos );
			token.value = token.rawValue.toString();
			token.type = TTDefaultVariable;
		}
		// Token is a variable
		else if ( token.type == TTVariable ) {
			// Is this a key?
			if (isKey){
				token.value = token.rawValue.toString();
				token.type = TTVariable;
			}
			// First see if variable is in user map
			else if ( variables.exists( token.rawValue.toString() ) ) {	
				token.value = variables.get(token.rawValue.toString());
			}
			// Next, check if the user has implemented onVariable
			else if ( onVariable != null ) {
				token.value = onVariable( token.rawValue.toString() );
			}
			// Otherwise, unhandled.
			// XXX: Option to ignore unhandled variables
			else {
				error( 'Unhandled variable "${token.rawValue}"', start );
			}
		}
		// Token is a string
		else if (token.type == TTString) {
			token.value = token.rawValue.toString();
		}
		// Token is unknown (number, constant or unquoted key)
		else if (token.type == TTUnknown) {
			// See if it's a number
			token.value = strToNum( token.rawValue.toString() );
			if ( token.type == TTUnknown ) {
				// Unquoted key
				if (isKey) {
					token.value = token.rawValue.toString();
				}
				// Constant
				else {
					switch( token.rawValue.toString().toUpperCase() ) {
						case 'PI': {
							token.value = Math.PI;
						}
						case 'PI_2': {
							token.value = Math.PI;
						}
						case 'INV_PI': {
							token.value = 1/Math.PI;
						}
						default: {
							if (onConstant != null){
								var d = onConstant( token.rawValue.toString() );
								token.value = (d==null)?token.rawValue.toString():d;
							}
							else {
								error( "Unhandled constant", token.pos );
							}
						}
					}
				}
			}
		}
		return token;
	}

	/**
	 * Process the function described by the token
	 * @param token 		Contains the function name and parameters
	 * @return Dynamic		The final result of the function call
	 */
	function processFunction( token : Token ) : Dynamic {
		var fn : String = token.rawValue.toString();
		switch (fn.toLowerCase()) {

			// Math

			case 'min': {
				if (!token.checkArgs( [ATNumber, ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float, Float)', token.pos );
				return Math.min( token.args[0].value, token.args[1].value );
			}
			case 'max': {
				if (!token.checkArgs( [ATNumber, ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float, Float)', token.pos );
				return Math.max( token.args[0].value, token.args[1].value );
			}
			case 'floor': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.floor( token.args[0].value );
			}
			case 'ceil': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.ceil( token.args[0].value );
			}
			case 'round': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.round( token.args[0].value );
			}
			case 'cos': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.cos( token.args[0].value );
			}
			case 'sin': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.sin( token.args[0].value );
			}
			case 'tan': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.tan( token.args[0].value );
			}
			case 'acos': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.acos( token.args[0].value );
			}
			case 'asin': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.asin( token.args[0].value );
			}
			case 'atan': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.atan( token.args[0].value );
			}
			case 'atan2': {
				if (!token.checkArgs( [ATNumber, ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float, Float)', token.pos );
				return Math.atan2( token.args[0].value, token.args[1].value );
			}
			case 'sqrt': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.sqrt( token.args[0].value );
			}
			case 'pow': {
				if (!token.checkArgs( [ATNumber, ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float, Float)', token.pos );
				return Math.pow( token.args[0].value, token.args[1].value );
			}
			case 'abs': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.abs( token.args[0].value );
			}
			case 'clamp': {
				if (token.checkArgs( [ATNumber,ATNumber,ATNumber] )) return Math.clamp( token.args[0].value, token.args[1].value, token.args[2].value );
				if (token.checkArgs( [ATNumber,ATNumber] )) return Math.clamp( token.args[0].value, token.args[1].value );
				if (token.checkArgs( [ATNumber] )) return Math.clamp( token.args[0].value );
				error( 'Incorrect args for "$fn". Expect (Float, [Float, [Float]] )', token.pos );
				return null;
			}
			case 'lerp': {
				if (!token.checkArgs( [ATNumber, ATNumber, ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float,Float,Float)', token.pos );
				return Math.lerp( token.args[0].value, token.args[1].value, token.args[2].value );
			}
			case 'degtorad': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.degToRad( token.args[0].value );
			}
			case 'radtodeg': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.radToDeg( token.args[0].value );
			}
			case 'random': {
				if (!token.checkArgs( [ATNumber] )) error( 'Incorrect args for "$fn". Expect (Float)', token.pos );
				return Math.random( token.args[0].value );
			}

			// Color
			case 'rgb': {
				if (!token.checkArgs( [ATInt,ATInt,ATInt] )) error( 'Incorrect args for "$fn". Expect (Int, Int, Int)', token.pos );
				return ColorTools.colorFromRGB( token.args[0].value, token.args[1].value, token.args[2].value );
			}
			case 'rgba': {
				if (!token.checkArgs( [ATInt,ATInt,ATInt,ATNumber] )) error( 'Incorrect args for "$fn". Expect (Int, Int, Int, Float)', token.pos );
				return ColorTools.colorFromRGBa( token.args[0].value, token.args[1].value, token.args[2].value, token.args[3].value );
			}
			case 'alpha': {
				if (!token.checkArgs( [ATInt] )) error( 'Incorrect args for "$fn". Expect (Color)', token.pos );
				return ColorTools.alpha( token.args[0].value );
			}
			case 'red': {
				if (!token.checkArgs( [ATInt] )) error( 'Incorrect args for "$fn". Expect (Color)', token.pos );
				return ColorTools.red( token.args[0].value );
			}
			case 'green': {
				if (!token.checkArgs( [ATInt] )) error( 'Incorrect args for "$fn". Expect (Color)', token.pos );
				return ColorTools.green( token.args[0].value );
			}
			case 'blue': {
				if (!token.checkArgs( [ATInt] )) error( 'Incorrect args for "$fn". Expect (Color)', token.pos );
				return ColorTools.blue( token.args[0].value );
			}
			case 'opacity': {
				if (!token.checkArgs( [ATInt,ATNumber] )) error( 'Incorrect args for "$fn". Expect (Color, Float)', token.pos );
				return ColorTools.opacity( token.args[0].value, token.args[1].value );
			}
			case 'darken': {
				if (!token.checkArgs( [ATInt,ATNumber] )) error( 'Incorrect args for "$fn". Expect (Color, Float)', token.pos );
				return ColorTools.darken( token.args[0].value, token.args[1].value );
			}
			case 'lighten': {
				if (!token.checkArgs( [ATInt,ATNumber] )) error( 'Incorrect args for "$fn". Expect (Color, Float)', token.pos );
				return ColorTools.lighten( token.args[0].value, token.args[1].value );
			}
			case 'tint': {
				if (!token.checkArgs( [ATInt,ATInt,ATNumber] )) error( 'Incorrect args for "$fn". Expect (Color, Color, Float)', token.pos );
				return ColorTools.tint( token.args[0].value, token.args[1].value, token.args[2].value );
			}

			default: {
				if (onFunction==null) error( 'Unknown function "$fn"', token.pos );
				var args : Array<Dynamic> = new Array();
				for (t in token.args) args.push( t.value );
				var res : Dynamic = onFunction( fn, args );
				if (res == null) error( 'Unknown function "$fn"', token.pos );
				return res;
			}
		}
	}

	/**
	 * Std.parseFloat is pretty good, but it doesn't handle binary 0b1001110 or #fff colors.
	 * @param str 		The string to convert
	 * @return Dynamic	The Int or Float result
	 */
	public function strToNum( str : String ) : Dynamic {
		// Parse # colors
		if( str.fastCodeAt(0)=='#'.code ) {
			if( str.length == 4 ) {
				return Std.parseInt( '0x'+str.charAt(1)+str.charAt(1)+str.charAt(2)+str.charAt(2)+str.charAt(3)+str.charAt(3) );
			}
			else if( str.length == 7 ) {
				return Std.parseInt( '0x'+str.substr(1) );
			}
			else
				throw 'Unknown hex format "$str"';
		}
		// Check for 0x0 or 0b0
		else if( str.fastCodeAt(0)=='0'.code ) {
			// Parse hex format
			if( (str.fastCodeAt(1)=='x'.code) || (str.fastCodeAt(1)=='X'.code) ) {
				return Std.parseInt( str );
			}
			// Parse binary format
			if( (str.fastCodeAt(1)=='b'.code) || (str.fastCodeAt(1)=='B'.code) ) {
				var i = 0;
				var v : Int = 0;
				var index = str.length-1;
				while( index > 1 ) {
					if( str.fastCodeAt(index)=='1'.code ) v += Std.int( Math.pow( 2, i ) );
					i++;
					index--;
				}
				return v;
			}
		}
		// Parse float or int
		var f = Std.parseFloat( str );
		var i = Std.int( f );
		return (i == f)?i:f;
	}

	inline function unexpected( t : Token ) {
		var desc = '';
		switch (t.type){
			case TTOperator(t): desc = ' TTOperator("'+String.fromCharCode(t)+'")';
			case TTString, TTNumber, TTFunction: desc = ' "'+t.rawValue.toString()+'"';
			default: desc = ' '+t.type;
		}
		error( 'Unexpected token'+desc, t.pos );
	}

	inline function error( msg : String, pos : Int ) {
		throw msg + ' at ' + pos;
	}

	inline function next() {
		return str.fastCodeAt( pos++ );
	}

	inline function peek( offset:Int = 0 ) {
		return str.fastCodeAt( pos + offset );
	}

	inline function rewind( amount:Int = 1 ) {
		pos -= amount;
	}

}