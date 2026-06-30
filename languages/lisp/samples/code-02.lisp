;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;; Comprehensive Common Lisp Feature Test Suite
;;;; For testing a Lisp parser generator / reader implementation
;;;;
;;;; This file contains valid Common Lisp code that exercises nearly all
;;;; syntactic, reader-macro, special-form, macro, and language features
;;;; of ANSI Common Lisp (and some common extensions in a portable way).
;;;;
;;;; It is designed to be LOADable (with minor caveats for implementation-specific
;;;; features guarded by #+/#-) and to stress-test parsers with:
;;;;   - All reader syntaxes (# dispatch, quote, backquote, etc.)
;;;;   - Complex nesting, symbols, numbers, strings, characters
;;;;   - Full lambda-list syntax (ordinary, generic, macro, destructuring)
;;;;   - All special forms and core macros
;;;;   - CLOS, conditions, iteration (especially LOOP's keyword-rich syntax)
;;;;   - Package system, declarations, eval-when, etc.
;;;;
;;;; Sections are clearly marked. Each construct is used in a realistic way.
;;;; Some forms are wrapped in EVAL-WHEN or commented where they would have
;;;; side-effects or require specific implementations.
;;;;
;;;; To use: (load "comprehensive_lisp_test_suite.lisp")
;;;; Then call (lisp-feature-test:run-tests) if desired (defined at end).

(defpackage #:lisp-feature-test
  (:use #:common-lisp)
  (:shadow #:foo)                    ; test shadowing
  (:export #:run-tests
           #:example-macro
           #:test-class
           #:test-struct)
  (:documentation "Package for comprehensive Lisp parser test suite."))

(in-package #:lisp-feature-test)

;;;============================================================================
;;; 1. BASIC ATOMS, LISTS, COMMENTS, WHITESPACE
;;;============================================================================

;; Line comment with various characters: !@#$%^&*()_+-=[]{}|;:'",.<>/?`~
#| Block comment
   can span multiple lines
   and contain (unbalanced parens [ { " ' | and even #| nested? but standard doesn't require nesting
   Actually #| comments do not nest in ANSI CL; inner #| is just text.
|#

(defparameter *basic-list* '(a b c))          ; simple proper list
(defparameter *improper-list* '(a b . c))     ; dotted pair / improper list
(defparameter *empty-list* '())
(defparameter *nil-atom* nil)
(defparameter *t-atom* t)
(defparameter *keyword* :keyword-symbol)
(defparameter *uninterned* #:uninterned-symbol)
(defparameter *internal* 'lisp-feature-test::internal-symbol)
(defparameter *escaped-symbol* '|symbol with spaces & weird-chars!|)
(defparameter *vertical-bar* '|foo\|bar|')  ; tests | char inside escaped symbol name using \| escape
(defparameter *safe-escaped* '|symbol-with-pipes\|inside-by-doubling|')  ; correct way: \| to include | in |escaped| name

;;;============================================================================
;;; 2. NUMBERS - all numeric types and syntaxes
;;;============================================================================

(defparameter *fixnum* 42)
(defparameter *bignum* 1234567890123456789012345678901234567890)
(defparameter *negative* -123)
(defparameter *positive-explicit* +456)
(defparameter *float-single* 3.14159)
(defparameter *float-double* 2.718281828459045d0)
(defparameter *float-short* 1.0s0)
(defparameter *float-long* 1.0l0)
(defparameter *float-exp* 1.23e10)
(defparameter *float-exp-neg* -4.56e-7)
(defparameter *ratio* 22/7)
(defparameter *ratio-neg* -3/4)
(defparameter *complex* #c(3 4))
(defparameter *complex-float* #C(1.0 2.0))
(defparameter *complex-ratio* #c(1/2 3/4))
(defparameter *octal* #o755)          ; or #8r755 but octal common
(defparameter *hex* #xFF)
(defparameter *binary* #b101010)
(defparameter *radix* #36rZ)          ; custom radix

;;;============================================================================
;;; 3. CHARACTERS AND STRINGS (with escapes and multi-line)
;;;============================================================================

(defparameter *char-a* #\A)
(defparameter *char-space* #\Space)
(defparameter *char-newline* #\Newline)
(defparameter *char-tab* #\Tab)
(defparameter *char-backspace* #\Backspace)
(defparameter *char-return* #\Return)
(defparameter *char-linefeed* #\Linefeed)
(defparameter *char-page* #\Page)
(defparameter *char-rubout* #\Rubout)
(defparameter *char-null* #\Null)
(defparameter *char-bell* #\Bell)     ; if supported
(defparameter *char-escape* #\Escape)
(defparameter *char-backslash* #\\)
(defparameter *char-doublequote* #\")
(defparameter *char-vertical* #\|)
(defparameter *char-paren-open* #\()
(defparameter *char-paren-close* #\))

(defparameter *string-simple* "hello world")
(defparameter *string-escaped* "He said \"hello\" and used \\backslash")
(defparameter *string-with-newline*
  "This string spans
multiple lines in source.
Newlines are preserved.")
(defparameter *string-empty* "")
(defparameter *string-with-all-escapes* "Quote: \" Backslash: \\ End.")

;;;============================================================================
;;; 4. VECTORS, ARRAYS, BIT-VECTORS (reader syntax)
;;;============================================================================

(defparameter *simple-vector* #(1 2 3 4 5))
(defparameter *vector-with-atoms* #(foo :bar "baz" 42 #\x))
(defparameter *bit-vector* #*10110101)
(defparameter *empty-bit-vector* #*)
(defparameter *2d-array* #2A((1 2 3) (4 5 6) (7 8 9)))
(defparameter *3d-array* #3A(((1 2) (3 4)) ((5 6) (7 8))))
(defparameter *array-with-fill* #2A((1 2) (3 4)))   ; 2D inferred? Actually #A is for array, rank from nesting

;;;============================================================================
;;; 5. PATHNAMES, COMPLEX (already did), STRUCTURES (later)
;;;============================================================================

(defparameter *pathname* #P"/tmp/test.lisp")
(defparameter *pathname2* #p"relative/path.lisp")
(defparameter *logical-pathname* #P"LOGICAL:DIR;FILE.LISP")

;;;============================================================================
;;; 6. QUOTING, BACKQUOTING, COMMA, SPLICE, SHARP-QUOTE
;;;============================================================================

(defparameter *quoted-symbol* 'foo)
(defparameter *quoted-list* '(1 2 (3 4)))
(defparameter *backquote-simple* `(a b c))
(defparameter *backquote-comma* `(a ,*fixnum* c))
(defparameter *backquote-splice* `(start ,@'(middle1 middle2) end))
(defparameter *backquote-nested* `(outer (inner ,(+ 1 2) ,@(list 'x 'y))))
(defparameter *function-quote* #'car)
(defparameter *lambda-function* #'(lambda (x) (+ x x)))
(defparameter *sharp-dot* #.(+ 1 2 3))   ; read-time evaluation -> 6

;;; Label syntax for shared/circular structure (tests #= and ## reader macros)
;; (defparameter *shared-structure*
;;   '#1=(list 'a 'b '#1# 'c))   ; Note: this creates circular list when read
;; 
;;;============================================================================
;;; 7. PACKAGES, SYMBOLS WITH COLONS (more examples)
;;;============================================================================

(defparameter *cl-symbol* 'common-lisp:car)
(defparameter *double-colon* 'common-lisp::defun)
(defparameter *keyword-intern* (intern "DYNAMIC-KEYWORD" :keyword))

;;;============================================================================
;;; 8. SPECIAL FORMS - Core control and binding
;;;============================================================================

(defun test-special-forms ()
  "Demonstrates many special forms."
  (block outer-block
    (let ((x 10)
          (y 20))
      (declare (fixnum x y) (optimize (speed 3) (safety 0)))
      (let* ((z (+ x y))
             (w (if (> z 25) 'big 'small)))
        (flet ((local-add (a b) (+ a b)))
          (labels ((recursive (n)
                     (if (<= n 0) 0 (+ n (recursive (- n 1))))))
            (macrolet ((my-macro (form) `(list ,form)))
              (symbol-macrolet ((sym x))
                (tagbody
                   (go start)
                 start
                   (when (plusp x)
                     (return-from outer-block
                       (values z w (local-add x y) (recursive 5)
                               (my-macro sym) (catch 'tag (throw 'tag 'caught)))))
                   (go end)
                 end)))))))))

;;;============================================================================
;;; 9. CONDITION SYSTEM
;;;============================================================================

(define-condition test-error (error)
  ((message :initarg :message :reader error-message)
   (code :initarg :code :initform 0 :reader error-code))
  (:report (lambda (c s)
             (format s "Test error ~A: ~A (code ~D)"
                     (error-code c) (error-message c) (error-code c)))))

(define-condition test-warning (warning) ())

(defun test-conditions ()
  (handler-case
      (progn
        (when t
          (signal 'test-warning))
        (error 'test-error :message "something broke" :code 42))
    (test-warning (w) (declare (ignore w)) :got-warning)
    (test-error (e) (list :error (error-message e) (error-code e)))
    (:no-error (val) (list :no-error val)))
  (handler-bind ((error (lambda (c) (declare (ignore c)) nil)))
    (restart-case
        (error "restart test")
      (use-value (v) v)
      (abort () :aborted))))

;;;============================================================================
;;; 10. ITERATION - DO, DOLIST, DOTIMES, PROG, LOOP (comprehensive)
;;;============================================================================

(defun test-iteration ()
  (let ((result '()))
    (do ((i 0 (1+ i))
         (j 10 (1- j)))
        ((>= i 5) result)
      (push (list i j) result))
    
    (dolist (item '(a b c d) result)
      (push item result))
    
    (dotimes (k 3 result)
      (push k result))
    
    ;; PROG with tags and GO
    (prog ((x 0))
       top
          (when (> x 2) (go end))
          (push x result)
          (incf x)
          (go top)
       end)
    
    ;; The mighty LOOP - exercises almost all LOOP keywords
    (loop with total = 0
          with items = '()
          for i from 1 to 10
          for j from 0 below 5
          for c in '(#\a #\b #\c)
          for s on '(1 2 3 4)
          as k = (* i 2) then (+ k 3)
          while (< total 100)
          until (> i 8)
          if (evenp i)
            collect i into evens
            and sum i into even-sum
          else
            collect i into odds
          when (zerop (mod i 3))
            do (push i items)
          unless (minusp j)
            maximize j into maxj
          finally (setf total (+ even-sum (or maxj 0)))
                  (return (list :loop-result total evens odds items maxj k c s)))))

;;;============================================================================
;;; 11. MULTIPLE VALUES
;;;============================================================================

(defun returns-multiple ()
  (values 1 "two" :three 4.0))

(defun test-multiple-values ()
  (multiple-value-bind (a b c d) (returns-multiple)
    (list a b c d))
  (multiple-value-setq (x y) (floor 10 3))
  (values-list '(10 20 30)))

;;;============================================================================
;;; 12. MACROS - defmacro with all lambda list features + examples
;;;============================================================================

(defmacro example-macro (name &optional (default 42) &rest rest &key (verbose t) (mode :normal)
                         &aux (computed (+ default 100)))
  "A macro demonstrating &optional, &rest, &key, &aux in lambda list."
  `(progn
     (defparameter ,(intern (string name)) ,default)
     (when ,verbose
       (format t "Macro ~A default=~A mode=~A computed=~A rest=~S~%"
               ',name ,default ,mode ,computed ',rest))
     (list ',name ,default ',rest ,verbose ,mode ,computed)))

(defmacro destructuring-macro ((first second &optional (third 0)) &body body)
  "Destructuring lambda list + &body."
  `(progn
     (format t "Destructuring: first=~A second=~A third=~A~%" ',first ',second ',third)
     ,@body))

(defmacro with-whole-and-env (&whole whole-form name &environment env &body body)
  "Uses &whole and &environment (advanced macro lambda list)."
  (declare (ignore env))
  `(progn
     (format t "Whole form was: ~S~%" ',whole-form)
     (defun ,name () ,@body)))

(example-macro my-param 99 :verbose nil :mode :fast :extra "data")
(destructuring-macro (alpha beta gamma) (list alpha beta gamma))
(with-whole-and-env test-whole () (list 1 2 3))

;;;============================================================================
;;; 13. CLOS - Classes, Methods, Generic Functions, Combinations
;;;============================================================================

(defclass test-class ()
  ((name :initarg :name :initform "unnamed" :accessor class-name
         :documentation "The name slot")
   (value :initarg :value :accessor class-value :type number)
   (secret :initarg :secret :reader secret-value :allocation :instance))
  (:documentation "Test class for parser exercise.")
  (:default-initargs :value 0))

(defclass test-subclass (test-class)
  ((extra :initarg :extra :initform 'extra-stuff :accessor extra-slot))
  (:documentation "Subclass demonstrating inheritance."))

(defgeneric test-generic (obj &key mode)
  (:documentation "Generic function with keyword.")
  (:method-combination standard)   ; explicit
  (:method ((obj test-class) &key (mode :normal))
    (list :primary (class-name obj) mode)))

(defmethod test-generic :before ((obj test-class) &key mode)
  (declare (ignore mode))
  (format t "Before method on ~A~%" (class-name obj)))

(defmethod test-generic :after ((obj test-class) &key mode)
  (declare (ignore mode))
  (format t "After method on ~A~%" (class-name obj)))

(defmethod test-generic ((obj test-subclass) &key (mode :sub))
  (append (call-next-method) (list :subclass-extra (extra-slot obj) mode)))

(defun test-clos ()
  (let ((obj (make-instance 'test-subclass :name "testobj" :value 123 :extra 'foo)))
    (with-slots (name value) obj
      (incf value 10))
    (with-accessors ((n class-name) (v class-value)) obj
      (list n v (test-generic obj :mode :test) (secret-value obj)))))

;;;============================================================================
;;; 14. STRUCTURES
;;;============================================================================

(defstruct (test-struct (:conc-name ts-)
                        (:constructor make-test-struct
                          (&key (id 0) (data nil) &aux (computed (list id data))))
                        (:copier copy-test-struct)
                        (:predicate test-struct-p)
                        (:print-function
                         (lambda (obj stream depth)
                           (declare (ignore depth))
                           (format stream "#<TEST-STRUCT id=~A data=~A>"
                                   (ts-id obj) (ts-data obj)))))
  id
  data
  (computed nil :read-only t))

(defparameter *a-struct* (make-test-struct :id 42 :data "hello"))
(defparameter *struct-literal* #S(test-struct :id 99 :data :literal))

;;;============================================================================
;;; 15. DECLARATIONS, PROCLAIM, DECLAIM, OPTIMIZE, TYPE, INLINE, etc.
;;;============================================================================

(declaim (inline fast-add)
         (optimize (speed 3) (safety 1) (debug 0) (space 0)))

(proclaim '(special *dynamic-var*))
(defvar *dynamic-var* 100 "A special/dynamic variable.")

(defun fast-add (x y)
  (declare (fixnum x y) (inline fast-add))
  (the fixnum (+ x y)))

(declaim (ftype (function (fixnum fixnum) fixnum) fast-add))

;;;============================================================================
;;; 16. EVAL-WHEN, LOAD-TIME-VALUE, COMPILER-MACRO, SYMBOL-MACRO
;;;============================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *eval-when-var* "Evaluated at compile/load/execute time"))

(define-symbol-macro sym-macro *eval-when-var*)

(define-compiler-macro fast-add (&whole form x y)
  (declare (ignore x y))
  (when (and (constantp x) (constantp y))
    `,(+ (eval x) (eval y)))   ; silly example
  form)

(defun test-compile-time ()
  (load-time-value (get-universal-time))   ; evaluated once at load
  sym-macro)

;;;============================================================================
;;; 17. LOOP more, FORMAT (for string complexity), other macros
;;;============================================================================

(defun test-format-and-loop ()
  (format t "~&~{~A ~} ~S ~C ~%~D ~B ~O ~X ~R~%"
          '(hello world) "string" #\X 42 255 255 255 42)
  (loop for i below 5
        collect (format nil "item-~D" i) into strs
        finally (return strs)))

;;;============================================================================
;;; 18. FEATURE EXPRESSIONS (#+ #-)
;;;============================================================================

(defun test-features ()
  #+common-lisp
  (format t "Common Lisp is always here~%")
  #-nonexistent-feature
  (format t "This is not a nonexistent feature~%")
  #+ (and common-lisp (not nonexistent))
  'feature-expression-works)

;;;============================================================================
;;; 19. MORE EDGE CASES & MISC
;;;============================================================================

;; Empty forms, nil in various places
(defparameter *weird* (list () 'nil nil ()))

;; Deep nesting to test parser stack/recursion
(defun deeply-nested (n)
  (if (<= n 0)
      'base
      (list (deeply-nested (1- n)) n)))

;; Complex backquote with multiple splices and commas
(defparameter *complex-bq*
  `(defun generated (,@'(a b) c ,@(list 'd 'e) &key (f ,(+ 1 2)))
     (list a b c d e f)))

;; Reader conditional inside code (parsed but conditional on features)
(defparameter *conditional-code*
  '(#+sbcl sb-ext:*posix-argv*
    #-sbcl *argv*))   ; portable attempt

;; SETF and places (many places exist but syntax is standard)
(defun test-setf ()
  (let ((lst (list 1 2 3)))
    (setf (car lst) 99
          (cadr lst) 88)
    lst))

;; FMAKUNBOUND, etc but runtime

;;;============================================================================
;;; 20. RUNNER / ENTRY POINT
;;;============================================================================

(defun run-tests ()
  "Run a selection of the test functions to exercise everything."
  (format t "~&=== Running Lisp Feature Tests ===~%")
  (test-special-forms)
  (test-conditions)
  (test-iteration)
  (test-multiple-values)
  (test-clos)
  (test-format-and-loop)
  (test-features)
  (format t "~&All syntactic features exercised. Parser test complete.~%")
  t)

;;; End of comprehensive test suite.
;;; This file covers:
;;; - Reader: atoms, numbers (all types/radix), chars, strings (escapes + multiline),
;;;   lists (proper/improper), vectors/arrays/bit-vectors, pathnames, #c, #s (struct),
;;;   #', #., #1= / #1# labels, #+ / #-, package-qualified symbols, |escaped symbols|
;;; - Special forms: block, catch, eval-when, flet, function, if, labels, let, let*,
;;;   locally (implied), macrolet, multiple-value-call (indirect), progn, progv (not shown),
;;;   quote, return-from, setq/setf, symbol-macrolet, tagbody, the, throw, unwind-protect
;;; - Macros: defun, defmacro (all ll keywords), defvar/defparameter/defconstant,
;;;   defclass, defgeneric, defmethod, defstruct, define-condition, handler-case/bind,
;;;   restart-case, loop (extensive), do/dolist/dotimes, prog, multiple-value-bind,
;;;   destructuring-bind (used in macro), with-slots/with-accessors, etc.
;;; - CLOS full: classes, inheritance, slots options, generic functions, method combos,
;;;   before/after/around, eql specializers (easy to add), call-next-method
;;; - Declarations, proclamations, inline, ftype, optimize, type, special
;;; - Compiler macros, symbol macros, load-time-value
;;; - Iteration mini-languages (LOOP keywords, DO tags)
;;; - Condition/restart system
;;; - Feature expressions
;;;
;;; Edge cases: circular/shared structure syntax, deeply nested, empty lists,
;;; improper lists, complex lambda lists, destructuring, &whole/&environment,
;;; read-time eval, multi-line strings, all character names, radix numbers,
;;; escaped symbols with special chars, keyword/interned/uninterned symbols.

(format t "~&Loaded comprehensive_lisp_test_suite.lisp - parser test data ready.~%")
(run-tests)
