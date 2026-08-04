# Scientific calculator — driven by real clicks, checked by reading the screen.
# Every case starts from a cleared display.
reset click Clear

arithmetic          | click 7; click ×; click 8; click =            | text 56
precedence          | click 2; click +; click 3; click ×; click 4; click = | text 14
parentheses         | click (; click 2; click +; click 3; click ); click ×; click 4; click = | text 20
decimals            | click 1; click .; click 5; click +; click 2; click .; click 5; click = | text 4
negative result     | click 9; click -; click 1; click 5; click =   | text -6
divide              | click 8; click ÷; click 2; click =            | text 4
square root         | click 9; click √; click =                     | text 3
x squared           | click 7; click x²; click =                    | text 49
power               | click 2; click xʸ; click 1; click 0; click =  | text 1024
factorial           | click 5; click n!; click =                    | text 120
log base ten        | click 1; click 0; click 0; click log; click = | text 2
natural log of one  | click 1; click ln; click =                    | text 0
sin of zero         | click 0; click sin; click =                   | text 0
cos of zero         | click 0; click cos; click =                   | text 1
pi                  | click π                                       | text 3.14
euler               | click e                                       | text 2.71
percent             | click 5; click 0; click %                     | text 0.5
sign toggle         | click 7; click ±                              | text -7
clear really clears | click 9; click 9; click Clear                 | text 0
divide by zero      | click 5; click ÷; click 0; click =            | silence
