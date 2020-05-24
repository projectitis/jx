# jx
JX is a file format based on [JSON](https://www.json.org/json-en.html). JX was designed specifically for configuration files, but has a wide range of potential applications. JSON was designed to be lightweight with minimal rules. JX (Json eXtra) is a super-set of JSON that supports core JSON but adds many more powerful features. For example:
* Inline and block comments
* Keys without quotes
* Single and double quotes
* Variables and equations (including user-variables)
* Color support and manipulation
* Look-back referencing

Here is an [example jx file](example.jx).

## Licence
The JX (Json eXtra) format and the parsers supplied here are Open-Source under the MIT licence (free for any use, personal or commercial, without attribution, but also without warranty).

## Supported languages
The library is developed using [Haxe](https://haxe.org). The great thing about Haxe is that it compiles to source code in other languages (such as PHP, c#, c++, Javascript etc), so JX is available in a wide range of languages!
* [Haxe](/src/haxe/)

## Status
Work in progress. Parser not yet complete.

## Versions
Current version v0.1 (June 2020)

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

## Quotes
Keys do not have to be quoted, as long as they do not contain whitespace or illegal characters.
````
{ ThisKey_is_not_quoted: "And it works" }
````
However, for both keys and strings, single and double quotes are supprted. A string may contain the other type of quote without escaping, but must escape quotes if they are the same as the surrounding quotes.
````
[
    "This is 'fine' to do";
    'And this is "also" fine';
    "You can \"escape\" like this";
    'and \'like\' this';
]
````

## Values
The standard JSON values are supported, including `String`, `Number`, `true`, `false`, `null`. However, additional value types are supported.

### Number
As well as decimal integers or floats (`-12`, `14.99`), numbers can also be extressed as hexidecimal (`0xaa72`) or binary (`b10111001`).

### Color
Colors are actually just parsed to a number (integer), but can be expressed in different ways:
```
[
    #ff9900; // css hex format
    rgb( 255, 153, 0 ); // RGB format (0-255)
    rgba( 255, 153, 0, 0.4 ); // RGBA format where alpha is 0.0 - 1.0
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

## Look-back references
As well as variables, JX supports look-backs to reference any values that have already been set. Look-forwards are not supported. Look-backs should not be quoted, and as such none of the parts of the path may contain whitespace or illegal chaaracters. Array access is zero-based.
````
{
    foo: "Foo";
    bar: [
        "Hello";
        "World";
        {
            foo-bar: bar[1]; // Will be "World"
        }
    ];
    foo-bar: bar[2].foo-bar; // Will also be "World"
    name: foo; // Will be "Foo"
}
````
If the base element is an array:
````
[
    "Hello";
    "World";
    {
        foo-bar: [1]; // Will be "World"
        foo-bar-2: [2].foo-bar; // Will also be "World"
    }
]
````
