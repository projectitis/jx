# JX
JX (short for Json eXtended, file extension `.jx`) is a file format based on [JSON](https://www.json.org/json-en.html). JX was designed specifically for configuration files, but has a wide range of potential applications. JSON was designed to be lightweight with minimal rules. JX is a super-set of JSON that supports core JSON but adds many more powerful features. For example:
* Inline and block comments
* Keys without quotes
* Single and double quotes
* Variables and equations (including user-variables and default values)
* Color support and manipulation
* _Look-back referencing (not yet supported)_
* _Combining JX files (not yet supported)_

Here is an [example jx file](example.jx).

## Licence
The JX (Json eXtended) format and the parsers supplied here are Open-Source under the MIT licence (free for any use, personal or commercial, without attribution, but also without warranty).

## Supported languages
The library is developed using [Haxe](https://haxe.org). The great thing about Haxe is that it compiles to source code in other languages (such as PHP, c#, c++, Javascript etc), so JX is available in a wide range of languages!
* [Haxe](/src/haxe/)

## Status
Work in progress. Currently a fully working parser, with exceptions noted below (still in progress).

The current JxParser has dependencies on two other files and will not compile on it's own. These dependences will be removed in the next update. The only way to currently use JxParser is as part of the [heapsmore](https://github.com/projectitis/heapsmore) library.

## Versions
Current version v0.2 (August 2020)

## Comments
JX supports inline comments using __// comment__ and block comments using __/* comment */__. During parsing comments are treated as whitespace, so may occur anywhere that whitespace occurs. Be careful though, this can result in hard-to-read code. Just because you can doesn't mean you should!
````
/**
 * Comments and comment blocks (like this one) are supported outside of the root
 * object itself, as well as inside.
 **/
{
    // Comment are also supported inside object and arrays
    MyKey: "MyValue", // Comments are supported after variable definitions
   /* About to define key */ MyOtherKey /* Here coems the colon */ : /* About to set value */ "Another value" /* This is also ignored */ ; // The last comment can be inline
}
````

## Keys
Keys do not have to be quoted, as long as they do not contain whitespace characters. They may contain dots (e.g. `foo.bar: "FOOBAR"`) however, this may cause difficulties when using look-backs, so it is recommended to avoid them.
````
{ This_Key_is-not#quoted: "And it works" }
````

## Quotes
For both quoted keys and strings, single and double quotes are supported. A string may contain the other type of quote without escaping, but must escape quotes if they are the same as the enclosing quotes.
````
[
    "This is 'fine' to do",
    'And this is "also" fine';
    "You can \"escape\" like this",
    'and \'like\' this';
]
````
_Note that comma or semi-colon can be used to seperate values._

## Values
The standard JSON values are supported, including `String`, `Number`, `true`, `false`, `null`. However, additional value types are supported.

Values can be seperated by comma, or by semicolon (see the **quotes** example above)

### Number
As well as decimal integers or floats (`-12`, `14.99`), numbers can also be extressed as hexidecimal (`0xaa72`) or binary (`b10111001`).

### Color
Colors are actually just parsed to a number (integer), but can be expressed in different ways:
````
[
    #ff9900; // css hex format
    rgb( 255, 153, 0 ); // RGB format (0-255)
    rgba( 255, 153, 0, 0.4 ); // RGBA format where alpha is 0.0 - 1.0
]
````

### Strings
Strings can wrap lines and contain any whitespace present between the enclosing quotes. Escaped characters such as `\n` and `\t` are also supported. Also see notes on _Quotes_ above. These are examples of valid strings:
````
[
    "This is a long string on multiple lines.
    Beware - this second line starts with a tab character!
This is the third line of the string.";

    'Strings may contain "quotes" as long as they are not the same as the enclosing quotes.';

    "Strings may be enclosed with either single or double quotes.";
]
````

## Variables
Variables are denoted by a leading $. Variables always have global scope, no matter where they are defined, and can be used anywhere in the document _after_ they occur (no look-aheads).
````
{
    $baseColor: #ff9900;
    border-color: $baseColor;
}
````

### User variables
The user is able to define variables in the parser before parsing a jx file. These are then available as variables within the jx file. An example if `Haxe` is:
````
var jxParser = new JxParser( "{ myName: $name }", ["name"=>"Projectitis"] );
````

### Default values
To support user-variables, a default value can be specified inside the jx file. To do this, prefix the variable definition with a question mark (?). This will only set the value if the variable currently does not have one (i.e. the user has not defined it).
````
{
    ?$name: "The default name";
    myName: $name;
}
````

## Equations
Many math equations are supported directly within the JX document. This is useful in order to change values based on user-defined variables. A full suite of math functions are supported (`min`, `max`, `cos`, `sin`, `round`, `abs`, `random` etc) as well as a range of color manipulation functions such as `darken`, `lighten` and `tint`. String concatenation using + is also supported.
````
{
    ?$name: "The default name";
    ?$baseColor: rgb( 255, 153 ,0 );
    $highlightColor: #fff;
    ?$direction: 120;
    
    intro: "Hello " + $name;
    background-color: darken( $baseColor, 0.5 );
    foreground-color: tint( $baseColor, $highlightColor, 0.25 );
    window-x: sin( degToRad( $direction ) ) * 200;
    window-y: cos( degToRad( $direction ) ) * 200;
}
````

## Look-back references (not yet supported)
As well as variables, JX supports look-backs to reference any values that have already been set. Look-forwards are not supported.

Look-backs start with an equals sign (=) and may be quoted. Array access is zero-based. If a key in the path contains a space, it must be escaped by another dot (see below).
````
{
    foo: "Foo";
    foo.bar: "Has a dot in the key";
    bar: [
        "Hello";
        "World";
        {
            foo-bar: =bar[1]; // Will be "World"
        }
    ];
    foo-bar: =bar[2].foo-bar; // Will also be "World"
    name: =foo; // Will be "Foo"
    hasDot: ="foo.bar"; // Will be "Has a dot in the key";
}
````
If the base element is an array:
````
[
    "Hello";
    "World";
    {
        foo-bar: =[1]; // Will be "World"
        foo-bar-2: =[2].foo-bar; // Will also be "World"
    }
]
````

## Combining JX files (not yet supported)
JX allows combing multiple JX files together. This is useful if, for example, there is a default configuration file that contains all the available options, and then a second "user" config file that contains only a few items that need to change. To combine these, the default config is parsed first, and then the user config is parsed over the top of this. Depending on the implementation, this could be achieved by passing in a list of JX files to parse (in order), or by parsing one file first and then passing this in to the second parse as the 'base' data object.
````
// Example in haxe
var user = JxParser.parse( [defaultConfig, userConfig] );
// or
var base = JxParser.parse( defaultConfig );
var user = JxParser.parse( userConfig, base );
````
When combining JX files, the structure of the files must match or errors will result. For example, if one file has a key called `settings` that is an array (`[ ]`), and the other has a key called `settings` that is an object (`{ }`) or another type that is not an array (e.g. a String, Number etc) then a `type mismatch` error will be thrown.
