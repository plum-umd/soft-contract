(module onto racket
  (provide/contract
   [onto
    (->i ([A (any/c . -> . boolean?)])
	 (res₁ (A)
	      (->i ([callbacks (listof procedure?)])
		   (res₂ (callbacks)
			 (->i ([f (or/c false? string? (A . -> . any/c))])
			      (res₃ (f) (->i ([obj (and/c
						    A
						    (cond
						     [(false? f) (any/c . -> . any/c)]
						     [(string? f)
						      (->i ([k any/c])
							   (resₖ (k) (if (equal? k f) (A . -> . any/c) any/c)))]
						     [else any/c]))])
					     (res₄ (obj) (listof procedure?)))))))))])
  (define (onto A)
    (λ (callbacks)
      (λ (f)
        (λ (obj)
          (if (false? f) (cons obj callbacks)
              (let [cb (if (string? f) (obj f) f)]
                (cons (λ () (cb obj)) callbacks))))))))

(require 'onto)
((((onto •) •) •) •)