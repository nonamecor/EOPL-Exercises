#lang eopl

;; Exercise 7.9 [★★] Add listof types to the language, with operations similar to those of exercise 3.9. A value is of
;; type listof t if and only if it is a list and all of its elements are of type t. Extend the language with the
;; productions
;;
;;     Type       ::= listof Type
;;                    ┌────────────────┐
;;                    │ list-type (ty) │
;;                    └────────────────┘
;;     Expression ::= list (Expression {, Expression}∗)
;;                    ┌──────────────────────┐
;;                    │ list-exp (exp1 exps) │
;;                    └──────────────────────┘
;;     Expression ::= cons (Expression , Expression)
;;                    ┌──────────────────────┐
;;                    │ cons-exp (exp1 exp2) │
;;                    └──────────────────────┘
;;     Expression ::= null? (Expression)
;;                    ┌─────────────────┐
;;                    │ null-exp (exp1) │
;;                    └─────────────────┘
;;     Expression ::= emptylist [Type]
;;                    ┌────────────────────┐
;;                    │ emptylist-exp (ty) │
;;                    └────────────────────┘
;;
;; with types given by the following four rules:
;;
;;                    (type-of e1 tenv) = t
;;                    (type-of e2 tenv) = t
;;                                      ⋮
;;                    (type-of en tenv) = t
;;     ---------------------------------------------------
;;      (type-of (list-exp e1 (e2 … en)) tenv) = listof t
;;
;;            (type-of e1 tenv) = t
;;            (type-of e2 tenv) = listof t
;;     ------------------------------------------
;;      (type-of «cons(e1, e2)» tenv) = listof t
;;
;;        (type-of e1 tenv) = listof t
;;     -----------------------------------
;;      (type-of «null?(e1)» tenv) = bool
;;
;;     (type-of «emptylist[t]» tenv) = listof t
;;
;; Although cons is similar to pair, it has a very different typing rule.
;;
;; Write similar rules for car and cdr, and extend the checker to handle these as well as the other expressions. Use a
;; trick similar to the one in exercise 7.8 to avoid conflict with proc-type-exp. These rules should guarantee that car
;; and cdr are applied to lists, but they should not guarantee that the lists be non-empty. Why would it be unreasonable
;; for the rules to guarantee that the lists be non-empty? Why is the type parameter in emptylist necessary?

;; Grammar.

(define the-lexical-spec
  '([whitespace (whitespace) skip]
    [comment ("%" (arbno (not #\newline))) skip]
    [identifier (letter (arbno (or letter digit "_" "-" "?"))) symbol]
    [number (digit (arbno digit)) number]
    [number ("-" digit (arbno digit)) number]))

(define the-grammar
  '([program (expression) a-program]
    [expression (number) const-exp]
    [expression ("-" "(" expression "," expression ")") diff-exp]
    [expression ("zero?" "(" expression ")") zero?-exp]
    [expression ("if" expression "then" expression "else" expression) if-exp]
    [expression (identifier) var-exp]
    [expression ("let" identifier "=" expression "in" expression) let-exp]
    [expression ("proc" "(" identifier ":" type ")" expression) proc-exp]
    [expression ("(" expression expression ")") call-exp]
    [expression ("letrec" type identifier "(" identifier ":" type ")" "=" expression "in" expression) letrec-exp]
    [expression ("list" "(" expression (arbno "," expression) ")") list-exp]
    [expression ("cons" "(" expression "," expression ")") cons-exp]
    [expression ("null?" "(" expression ")") null-exp]
    [expression ("emptylist" "[" type "]") emptylist-exp]
    [expression ("car" "(" expression ")") car-exp]
    [expression ("cdr" "(" expression ")") cdr-exp]
    [type ("int") int-type]
    [type ("bool") bool-type]
    [type ("(" type "->" type ")") proc-type]
    [type ("listof" type) list-type]))

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define scan&parse (sllgen:make-string-parser the-lexical-spec the-grammar))

;; Data structures - expressed values.

(define-datatype proc proc?
  [procedure [bvar symbol?]
             [body expression?]
             [env environment?]])

(define-datatype expval expval?
  [num-val [value number?]]
  [bool-val [boolean boolean?]]
  [proc-val [proc proc?]]
  [list-val [head expval?]
            [tail expval?]]
  [emptylist-val])

(define expval-extractor-error
  (lambda (variant value)
    (eopl:error 'expval-extractors "Looking for a ~s, found ~s" variant value)))

(define expval->num
  (lambda (v)
    (cases expval v
      [num-val (num) num]
      [else (expval-extractor-error 'num v)])))

(define expval->bool
  (lambda (v)
    (cases expval v
      [bool-val (bool) bool]
      [else (expval-extractor-error 'bool v)])))

(define expval->proc
  (lambda (v)
    (cases expval v
      [proc-val (proc) proc]
      [else (expval-extractor-error 'proc v)])))

(define expval->list
  (lambda (v f)
    (cases expval v
      [list-val (head tail) (f head tail)]
      [else (expval-extractor-error 'list v)])))

;; Data structures - environment.

(define-datatype environment environment?
  [empty-env]
  [extend-env [bvar symbol?]
              [bval expval?]
              [saved-env environment?]]
  [extend-env-rec [p-name symbol?]
                  [b-var symbol?]
                  [p-body expression?]
                  [saved-env environment?]])

(define apply-env
  (lambda (env search-sym)
    (cases environment env
      [empty-env () (eopl:error 'apply-env "No binding for ~s" search-sym)]
      [extend-env (bvar bval saved-env) (if (eqv? search-sym bvar)
                                            bval
                                            (apply-env saved-env search-sym))]
      [extend-env-rec (p-name b-var p-body saved-env) (if (eqv? search-sym p-name)
                                                          (proc-val (procedure b-var p-body env))
                                                          (apply-env saved-env search-sym))])))

;; Data structures - type environment.

(define-datatype type-environment type-environment?
  [empty-tenv-record]
  [extended-tenv-record [sym symbol?]
                        [type type?]
                        [tenv type-environment?]])

(define apply-tenv
  (lambda (tenv sym)
    (cases type-environment tenv
      [empty-tenv-record () (eopl:error 'apply-tenv "Unbound variable ~s" sym)]
      [extended-tenv-record (sym1 val1 old-env) (if (eqv? sym sym1)
                                                    val1
                                                    (apply-tenv old-env sym))])))

(define empty-tenv empty-tenv-record)
(define extend-tenv extended-tenv-record)

;; Checker.

(define type-to-external-form
  (lambda (ty)
    (cases type ty
      [int-type () 'int]
      [bool-type () 'bool]
      [proc-type (arg-type result-type) (list (type-to-external-form arg-type)
                                              '->
                                              (type-to-external-form result-type))]
      [list-type (ty) (list 'listof (type-to-external-form ty))])))

(define report-unequal-types
  (lambda (ty1 ty2 exp)
    (eopl:error 'check-equal-type!
                "Types didn't match: ~s != ~a in~%~a"
                (type-to-external-form ty1)
                (type-to-external-form ty2)
                exp)))

(define check-equal-type!
  (lambda (ty1 ty2 exp)
    (when (not (equal? ty1 ty2))
      (report-unequal-types ty1 ty2 exp))))

(define report-rator-not-a-proc-type
  (lambda (rator-type rator)
    (eopl:error 'type-of-expression
                "Rator not a proc type:~%~s~%had rator type ~s"
                rator
                (type-to-external-form rator-type))))

(define report-rator-not-a-list-type
  (lambda (rator-type rator)
    (eopl:error 'type-of-expression
                "Rator not a list type:~%~s~%had rator type ~s"
                rator
                (type-to-external-form rator-type))))

(define type-of
  (lambda (exp tenv)
    (cases expression exp
      [const-exp (num) (int-type)]
      [var-exp (var) (apply-tenv tenv var)]
      [diff-exp (exp1 exp2) (let ([ty1 (type-of exp1 tenv)]
                                  [ty2 (type-of exp2 tenv)])
                              (check-equal-type! ty1 (int-type) exp1)
                              (check-equal-type! ty2 (int-type) exp2)
                              (int-type))]
      [zero?-exp (exp1) (let ([ty1 (type-of exp1 tenv)])
                          (check-equal-type! ty1 (int-type) exp1)
                          (bool-type))]
      [if-exp (exp1 exp2 exp3) (let ([ty1 (type-of exp1 tenv)]
                                     [ty2 (type-of exp2 tenv)]
                                     [ty3 (type-of exp3 tenv)])
                                 (check-equal-type! ty1 (bool-type) exp1)
                                 (check-equal-type! ty2 ty3 exp)
                                 ty2)]
      [let-exp (var exp1 body) (let ([exp1-type (type-of exp1 tenv)])
                                 (type-of body (extend-tenv var exp1-type tenv)))]
      [proc-exp (var var-type body) (let ([result-type (type-of body (extend-tenv var var-type tenv))])
                                      (proc-type var-type result-type))]
      [call-exp (rator rand) (let ([rator-type (type-of rator tenv)]
                                   [rand-type (type-of rand tenv)])
                               (cases type rator-type
                                 [proc-type (arg-type result-type) (begin (check-equal-type! arg-type rand-type rand)
                                                                          result-type)]
                                 [else (report-rator-not-a-proc-type rator-type rator)]))]
      [letrec-exp (p-result-type p-name b-var b-var-type p-body letrec-body)
                  (let ([tenv-for-letrec-body (extend-tenv p-name (proc-type b-var-type p-result-type) tenv)])
                    (let ([p-body-type (type-of p-body (extend-tenv b-var b-var-type tenv-for-letrec-body))])
                      (check-equal-type! p-body-type p-result-type p-body)
                      (type-of letrec-body tenv-for-letrec-body)))]
      [list-exp (exp1 exps) (let ([ty1 (type-of exp1 tenv)])
                              (let loop ([exps exps])
                                (if (null? exps)
                                    (list-type ty1)
                                    (let ([exp (car exps)])
                                      (check-equal-type! (type-of exp tenv) ty1 exp)
                                      (loop (cdr exps))))))]
      [cons-exp (exp1 exp2) (let ([ty1 (type-of exp1 tenv)]
                                  [ty2 (type-of exp2 tenv)])
                              (check-equal-type! ty2 (list-type ty1) exp2)
                              ty2)]
      [null-exp (exp1) (let ([ty1 (type-of exp1 tenv)])
                         (cases type ty1
                           [list-type (ty1) (bool-type)]
                           [else (report-rator-not-a-list-type ty1 exp1)]))]
      [emptylist-exp (ty) (list-type ty)]
      [car-exp (exp1) (let ([ty1 (type-of exp1 tenv)])
                        (cases type ty1
                          [list-type (ty2) ty2]
                          [else (report-rator-not-a-list-type ty1 exp1)]))]
      [cdr-exp (exp1) (let ([ty1 (type-of exp1 tenv)])
                        (cases type ty1
                          [list-type (ty2) ty1]
                          [else (report-rator-not-a-list-type ty1 exp1)]))])))

(define type-of-program
  (lambda (pgm)
    [cases program pgm (a-program (exp1) (type-of exp1 (empty-tenv)))]))

;; Interpreter.

(define apply-procedure
  (lambda (proc1 arg)
    (cases proc proc1
      [procedure (var body saved-env) (value-of body (extend-env var arg saved-env))])))

(define value-of
  (lambda (exp env)
    (cases expression exp
      [const-exp (num) (num-val num)]
      [var-exp (var) (apply-env env var)]
      [diff-exp (exp1 exp2) (let ([val1 (expval->num (value-of exp1 env))]
                                  [val2 (expval->num (value-of exp2 env))])
                              (num-val (- val1 val2)))]
      [zero?-exp (exp1) (let ([val1 (expval->num (value-of exp1 env))])
                          (if (zero? val1)
                              (bool-val #t)
                              (bool-val #f)))]
      [if-exp (exp0 exp1 exp2) (if (expval->bool (value-of exp0 env))
                                   (value-of exp1 env)
                                   (value-of exp2 env))]
      [let-exp (var exp1 body) (let ([val (value-of exp1 env)])
                                 (value-of body (extend-env var val env)))]
      [proc-exp (bvar ty body) (proc-val (procedure bvar body env))]
      [call-exp (rator rand) (let ([proc (expval->proc (value-of rator env))]
                                   [arg (value-of rand env)])
                               (apply-procedure proc arg))]
      [letrec-exp (ty1 p-name b-var ty2 p-body letrec-body) (value-of letrec-body
                                                                      (extend-env-rec p-name b-var p-body env))]
      [list-exp (exp1 exps) (let loop1 ([acc '()]
                                        [exp1 exp1]
                                        [exps exps])
                              (if (null? exps)
                                  (let loop2 ([acc-list (list-val (value-of exp1 env) (emptylist-val))]
                                              [vals acc])
                                    (if (null? vals)
                                        acc-list
                                        (loop2 (list-val (car vals) acc-list)
                                               (cdr vals))))
                                  (loop1 (cons (value-of exp1 env) acc)
                                         (car exps)
                                         (cdr exps))))]
      [cons-exp (exp1 exp2) (list-val (value-of exp1 env)
                                      (value-of exp2 env))]
      [null-exp (exp1) (cases expval (value-of exp1 env)
                         [emptylist-val () (bool-val #t)]
                         [else (bool-val #f)])]
      [emptylist-exp (ty) (emptylist-val)]
      [car-exp (exp1) (expval->list (value-of exp1 env)
                                    (lambda (head tail)
                                      head))]
      [cdr-exp (exp1) (expval->list (value-of exp1 env)
                                    (lambda (head tail)
                                      tail))])))

(define value-of-program
  (lambda (pgm)
    (cases program pgm
      [a-program (body) (value-of body (empty-env))])))

;; Interface.

(define check
  (lambda (string)
    (type-to-external-form (type-of-program (scan&parse string)))))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

(provide bool-val check emptylist-val list-val num-val run)
