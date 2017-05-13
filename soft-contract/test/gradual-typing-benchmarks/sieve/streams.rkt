#lang racket/base

(require racket/contract)
(require racket/match)

;; Simple streams library.
;; For building and using infinite lists.

(define stream/c (struct/c stream any/c (-> (recursive-contract stream/c #:chaperone))))

(provide (struct-out stream)
         (contract-out [make-stream (-> any/c any/c stream?)]
                       [stream-unfold (-> stream/c (cons/c any/c any/c))]
                       [stream-get (-> stream/c integer? any/c)]
                       [stream-take (-> stream/c integer? list?)]))

;; A stream is a cons of a value and a thunk that computes the next value when applied
(struct stream (first rest))

;;--------------------------------------------------------------------------------------------------

(define (make-stream hd thunk)
  (stream hd thunk))

;; `stream-unfold st` Destruct a stream `st` into its first value and the new stream produced by de-thunking the tail
(define (stream-unfold st)
  (cons (stream-first st) ((stream-rest st))))

;; `stream-get st i` Get the `i`-th element from the stream `st`
(define (stream-get st i)
  (match-define (cons hd tl) (stream-unfold st))
  (cond [(= i 0) hd]
        [else    (stream-get tl (sub1 i))]))

;; `stream-take st n` Collect the first `n` elements of the stream `st`.
(define (stream-take st n)
  (cond [(= n 0) '()]
        [else (match-define (cons hd tl) (stream-unfold st))
              (cons hd (stream-take tl (sub1 n)))]))