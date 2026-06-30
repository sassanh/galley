; -- Line comments 
; This file exercises the full Lisp grammar: lists, dotted pairs, vectors,
; bytevectors, booleans, characters, strings with escapes, numbers (integer,
; float, rational, hex/octal/binary), symbols (including + - -> :keyword),
; quote abbreviations, quasiquote/unquote, datum comments, and block comments.

#| Block comment: ignored entirely by the reader |#

; -- Booleans 
(define yes #true)
(define no  #false)
(define also-yes #t)
(define also-no  #f)

; -- Characters 
(define newline-char #\newline)
(define space-char   #\space)
(define tab-char     #\tab)
(define letter-a     #\a)
(define digit-zero   #\0)

; -- Strings with escape sequences 
(define greeting  "Hello, World!")
(define escaped   "tab:\there  newline:\nend")
(define with-quote "she said \"hello\"")
(define path      "C:\\Users\\lisp")

; -- Numbers: integers, floats, rationals, radix-prefixed 
(define n-int     42)
(define n-float   3.14159)
(define n-sci     6.022e23)
(define n-rat     1/3)           ; rational: one third
(define n-hex     #xff)          ; 255 in hex
(define n-oct     #o17)          ; 15 in octal
(define n-bin     #b1010)        ; 10 in binary

; -- Symbols: extended character set 
(define ->string  "converts to string")    ; -> as symbol
(define string->number 42)                 ; string->number as symbol
(define predicate? #t)                     ; ? suffix
(define set!-result 0)                     ; ! suffix
(define :keyword  "keyword value")         ; : prefix (Clojure-style keyword)
(define *global*  99)                      ; * delimited global
(define %private  0)                       ; % prefix

; -- Quote abbreviations 
(define quoted-list   '(a b c))
(define nested-quote  '(1 (2 3) (4 (5 6))))
(define quasi         `(list ,(+ 1 2) ,@(list 4 5)))

; -- Dotted pairs (improper lists) 
(define pair      (cons 1 . (2)))          ; equivalent to (cons 1 2)
(define alist-entry (key . value))

; -- Vectors 
(define vec  #(1 2 3 "four" #t))
(define nested-vec #(#(1 2) #(3 4)))

; -- Bytevectors 
(define bytes #u8(0 1 127 255))
(define header #u8(137 80 78 71))          ; PNG magic bytes

; -- Datum comment: the next form is silently ignored 
(define x #;(this form is ignored) 42)

; -- Core library functions 
(define square
  (lambda (x)
    (multiply x x)))

(define cube
  (lambda (x)
    (multiply x (multiply x x))))

(define factorial
  (lambda (n)
    (if (less-than n 2)
      1
      (multiply n (factorial (subtract n 1))))))

(define fibonacci
  (lambda (n)
    (if (less-than n 2)
      n
      (add
        (fibonacci (subtract n 1))
        (fibonacci (subtract n 2))))))

(define map
  (lambda (fn values)
    (if (empty values)
      ()
      (cons
        (fn (head values))
        (map fn (tail values))))))

(define reduce
  (lambda (fn initial values)
    (if (empty values)
      initial
      (reduce
        fn
        (fn initial (head values))
        (tail values)))))

; -- Application 
(define values
  (list 1 2 3 4 5 6 7 8 9 10 11 12))

(define squares (map square values))
(define cubes   (map cube values))
(define total   (reduce add 0 values))

(define weighted-total
  (reduce
    add
    0
    (map
      (lambda (value)
        (multiply value (add value 3)))
      values)))

(define report
  (lambda (label data)
    (print
      (list
        "report"
        label
        data
        (reduce add 0 data)))))

(report "squares" squares)
(report "cubes" cubes)
(print (list "total" total))
(print (list "weighted-total" weighted-total))
(print (list "factorial" (factorial 8)))
(print (list "fibonacci" (fibonacci 10)))

; -- Metadata 
(define program
  (list
    (list "name" "sample-lisp-program")
    (list "version" 2)
    (list "features"
      (list
        "line-comments"
        "block-comments"
        "booleans"
        "characters"
        "strings-with-escapes"
        "integers"
        "floats"
        "rationals"
        "hex-octal-binary-literals"
        "extended-symbols"
        "quote-abbreviations"
        "quasiquote"
        "dotted-pairs"
        "vectors"
        "bytevectors"
        "datum-comments"))
    (list "pipeline"
      (list
        (list "step" "load-values")
        (list "step" "map-square")
        (list "step" "map-cube")
        (list "step" "reduce-total")
        (list "step" "print-report")))))

(print program)
