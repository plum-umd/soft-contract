#lang typed/racket/base

;; This module implements the simplification of symbolic values
;; This is strictly not needed, but it simplifies/optimizes lots

(provide (all-defined-out))

(require (for-syntax racket/base
                     racket/syntax
                     syntax/parse
                     racket/contract
                     racket/match
                     racket/list
                     racket/function
                     (only-in "../utils/pretty.rkt" n-sub))
         racket/match
         (only-in racket/function curry)
         racket/set
         racket/bool
         racket/math
         racket/flonum
         racket/extflonum
         racket/string
         racket/vector
         racket/list
         "../utils/main.rkt"
         "../ast/main.rkt"
         "definition.rkt")

(: ?t@ : -h -?t * → -?t)
(define (?t@ f . xs)

  (: t@ : -h -t * → -t)
  ;; Smart constructor for term application
  (define (t@ f . xs)

    (: access-same-value? : -𝒾 (Listof -t) → (Option -t))
    ;; If given term list of the form `(car t); (cdr t)`, return `t`.
    ;; Otherwise just `#f`
    (define (access-same-value? 𝒾 ts)
      (define n (get-struct-arity 𝒾))
      (match ts
        [(cons (-t.@ (-st-ac 𝒾₀ 0) (list t₀)) ts*)
         (and (equal? 𝒾 𝒾₀)
              (for/and : Boolean ([i (in-range 1 n)] [tᵢ ts*])
                (match tᵢ
                  [(-t.@ (-st-ac 𝒾ⱼ j) (list tⱼ))
                   (and (equal? 𝒾 𝒾ⱼ) (= i j) (equal? t₀ tⱼ))]
                  [_ #f]))
              t₀)]
        [_ #:when (equal? n 0) (-t.@ (-st-mk 𝒾) '())]
        [_ #f]))

    (define (default-case) (-t.@ f xs))

    (match f
      ['any/c -tt]
      ['none/c -ff]
      ['void -void]
      ['values
       (match xs
         [(list x) x]
         [_ (default-case)])]

      ; vector-length
      ['vector-length
       (match xs
         [(list (-t.@ 'vector xs)) (-b (length xs))]
         [_ (default-case)])]

      ; (not³ e) = (not e) 
      ['not
       (match xs
         [(list (-t.@ 'not (list (and t* (-t.@ 'not _))))) t*]
         [(list (-t.@ 'not (list (-b x)))) (-b (not (not x)))]
         [(list (-b x)) (-b (not x))]
         [(list (-t.@ '<  (list x y))) (-t.@ '<= (list y x))]
         [(list (-t.@ '<= (list x y))) (-t.@ '<  (list y x))]
         [(list (-t.@ '>  (list x y))) (-t.@ '<= (list x y))]
         [(list (-t.@ '>= (list x y))) (-t.@ '<  (list x y))]
         [_ (default-case)])]
      ['not/c
       (match xs
         [(list (-t.@ 'not/c (list (and t* (-t.@ 'not/c _))))) t*]
         [_ (default-case)])]

      ; TODO: handle `equal?` generally
      [(? op-≡?)
       (match xs
         [(list (-b b₁) (-b b₂)) (if (equal? b₁ b₂) -tt -ff)]
         [(or (list t (-b #f)) (list (-b #f) t)) #:when t
          (-t.@ 'not (list t))]
         [(list x x) #:when (t-unique? x) -tt]
         [_ (default-case)])]

      ['defined?
        (match xs
          [(list (? -v?)) -tt]
          [_ (default-case)])]

      ['immutable?
       (match xs
         [(list (-t.@ 'vector _)) -ff] ; for now
         [_ (default-case)])]

      ['positive?
       (t@ '< (-b 0) (car xs))]
      ['negative?
       (t@ '< (car xs) (-b 0))]
      ['>
       (t@ '< (second xs) (first xs))]
      ['>=
       (t@ '<= (second xs) (first xs))]

      ; (car (cons e _)) = e
      [(-st-ac 𝒾 i)
       (match xs
         [(list (-t.@ (-st-mk (== 𝒾)) ts)) (list-ref ts i)]
         [_ (default-case)])]

      ; (cons (car e) (cdr e)) = e
      [(-st-mk s) (or (access-same-value? s xs) (default-case))]
      
      ; HACK
      ['+
       (match xs
         [(list b (-t.@ '- (list t b))) t]
         [_ (default-case)])]

      ; General case
      [_ (default-case)]))

  (and (andmap -t? xs) (apply t@ f xs)))

;; convenient syntax
(define-match-expander -t.not
  (syntax-rules () [(_ t) (-t.@ 'not (list t))])
  (syntax-rules () [(_ t) (and t (-t.@ 'not (list t)))]))

(define op-≡? (match-λ? '= 'equal? 'eq? 'char=? 'string=?))

(: -struct/c-split : -?t -𝒾 → (Listof -?t))
(define (-struct/c-split t 𝒾)
  (with-debugging/off
    ((ans)
     (define n (get-struct-arity 𝒾))
     (match t
       [(-t.@ (-st/c.mk (== 𝒾)) cs) cs]
       [(? values t)
        (for/list : (Listof -t) ([i n])
          (-t.@ (-st/c.ac 𝒾 i) (list t)))]
       [#f (make-list n #f)]))
    (printf "struct/c-split: ~a -> ~a~n" (show-t c) (map show-t ans))))

(: -struct-split : -?t -𝒾 → (Listof -?t))
(define (-struct-split t 𝒾)
  (match t
    [(-t.@ (-st-mk (== 𝒾)) ts) ts]
    [(? values t)
     (for/list : (Listof -t) ([i (get-struct-arity 𝒾)])
       (-t.@ (-st-ac 𝒾 i) (list t)))]
    [#f (make-list (get-struct-arity 𝒾) #f)]))

(: -ar-split : -?t → (Values -?t -?t))
(define (-ar-split t)
  (match t
    [(-t.@ (-ar.mk) (list c e)) (values c e)]
    [(? values t) (values (-t.@ (-ar.ctc) (list t))
                          (-t.@ (-ar.fun) (list t)))]
    [#f (values #f #f)]))

(: -->-split : -?t (U Index arity-at-least) → (Values (-maybe-var -?t) -?t))
(define (-->-split t shape)
  (define n
    (match shape
      [(arity-at-least n) (assert n index?)]
      [(? index? n) n]))
  (define var? (arity-at-least? shape))
  (match t
    [(-t.@ (-->.mk) (list cs ... d)) (values (cast cs (Listof -t)) d)]
    [(-t.@ (-->*.mk) (list cs ... cᵣ d)) (values (-var (cast cs (Listof -t)) cᵣ) d)]
    [(? values t)
     (define inits : (Listof -t)
       (for/list ([i : Index n])
         (-t.@ (-->.dom i) (list t))))
     (values (if var? (-var inits (-t.@ (-->.rst) (list t))) inits)
             (-t.@ (-->.rng) (list t)))]
    [#f
     (values (if var? (-var (make-list n #f) #f) (make-list n #f))
             #f)]))


(: -->i-split : -?t Index → (Values (Listof -?t) -?t))
(define (-->i-split t n)
  (match t
    [(-t.@ (-->i.mk) (list cs ... mk-d)) (values (cast cs (Listof -t)) mk-d)]
    [(? values t)
     (values (for/list : (Listof -t) ([i n])
               (-t.@ (-->i.dom i) (list t)))
             (-t.@ (-->i.rng) (list t)))]
    [#f (values (make-list n #f) #f)])) 

(define (-?list [ts : (Listof -?t)]) : -?t
  (foldr (curry ?t@ -cons) -null ts))

(define (-?unlist [t : -?t] [n : Natural]) : (Listof -?t)
  (let go ([t : -?t t] [n : Integer n])
    (cond [(> n 0) (cons (?t@ -car t) (go (?t@ -cdr t) (- n 1)))]
          [else '()])))

(: -app-split : -h -?t Integer → (Listof -?t))
(define (-app-split h t n)
  (match t
    [(-t.@ (== h) ts) ts]
    [_ (make-list n #f)]))

(: -?-> : (-maybe-var -?t) -?t -> -?t)
(define (-?-> cs d)
  (define cs* (check-ts cs))
  (and d cs* (-t.@ (-->.mk)
                  (match cs*
                    [(-var cs₀ cᵣ) `(,@cs₀ ,cᵣ ,d)]
                    [(? list? cs*) `(,@cs*     ,d)]))))



(: -?->i : (Listof -?t) (Option -λ) → -?t)
(define (-?->i cs mk-d)
  (and mk-d
       (let ([cs* (check-ts cs)])
         (and cs* (-t.@ (-->i.mk) `(,@cs* ,mk-d))))))

(: split-values : -?t Natural → (Listof -?t))
;; Split a pure term `(values t ...)` into `(t ...)`
(define (split-values t n)
  (match t
    [(-t.@ 'values ts)
     (cond [(= n (length ts)) ts]
           [else (error 'split-values "cannot split ~a values into ~a" (length ts) n)])]
    [(? values)
     (cond [(= 1 n) (list t)]
           [else
            (for/list ([i n])
              (-t.@ (-values.ac (assert i index?)) (list t)))])]
    [_ (make-list n #f)]))

(: check-ts (case->
             [(Listof -?t) → (Option (Listof -t))]
             [(-var -?t) → (Option (-var -t))]
             [(-maybe-var -?t) → (Option (-maybe-var -t))]))
(define (check-ts ts)

  (: go : (Listof -?t) → (Option (Listof -t)))
  (define (go ts)
    (match ts
      ['() '()]
      [(cons t ts*)
       (and t
            (let ([ts** (go ts*)])
              (and ts** (cons t ts**))))]))

  (match ts
    [(? list? ts) (go ts)]
    [(-var ts t)
     (and t
          (let ([ts* (go ts)])
            (and ts* (-var ts* t))))]))

#;(: e->t : -e -> -?t)
#;(define e->t
  (match-lambda
    [(-@ (? -h? h) es _)
     (define ?ts (maybe-map e->t es))
     (and ?ts (-t.@ h ?ts))]
    [(-struct/c 𝒾 cs _)
     (define ?ts (maybe-map e->t cs))
     (and ?ts (-t.@ (-st/c.mk 𝒾) ?ts))]
    [(-->i cs mk-d _)
     (define ?mk-d (e->t mk-d))
     (and ?mk-d
          (let ([?cs (maybe-map e->t cs)])
            (and ?cs (-t.@ (-->i.mk) `(,@?cs ,?mk-d)))))]
    [(--> cs d _)
     (define ?d )
     (cond
       [(e->t d) =>
        (λ ([?d : -t])
          (match cs
            [(-var cs₀ cᵣ)
             (define ?cᵣ (e->t cᵣ))
             (and ?cᵣ (let ([?cs₀ (maybe-map e->t cs₀)])
                        (and ?cs₀ (-t.@ (-->*.mk) `(,@?cs₀ ,?cᵣ ,?d)))))]
            [(? list? cs)
             (define ?cs (maybe-map e->t cs))
             (and ?cs (-t.@ (-->.mk) `(,@?cs ,?d)))]))]
       [else #f])]
    [(-λ (list x) (-if (-@ 'real? (list (-x x)) _)
                       (-@ (? -special-bin-o? o) (list (-x x) (-b b)) _)
                       (-b #f)))
     ((bin-o->h o) b)]
    [(? -t? t) t]
    [_ #f]))

(module+ test
  (require typed/rackunit)
  (check-equal? (?t@ 'not (?t@ 'not (?t@ 'not (-x 'x)))) (?t@ 'not (-x 'x)))
  (check-equal? (?t@ -car (?t@ -cons (-b 1) (-x 'x))) (-b 1))
  (let ([l (list -tt -ff (-x 'x) (-x 'y))])
    (check-equal? (-?unlist (-?list l) (length l)) l)))