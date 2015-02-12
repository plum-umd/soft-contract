#lang typed/racket/base
(require racket/set racket/list racket/match racket/bool racket/function
         "../utils.rkt" "../lang.rkt" "../runtime.rkt" "../show.rkt" "../provability.rkt" "delta.rkt")
(require/typed ; TODO for debugging only
 "read.rkt"
 [read-p (Any → .p)])
(provide (all-defined-out)) ; TODO

(define-data .κ
  (struct .if/κ [t : .E] [e : .E])
  (struct .@/κ [e* : (Listof .E)] [v* : (Listof .V)] [ctx : Symbol])
  (struct .▹/κ [ce : (U (Pairof #f .E) (Pairof .V #f))] [l^3 : Symbol^3])
  (struct .indy/κ
    [c : (Listof .V)] [x : (Listof .V)] [x↓ : (Listof .V)]
    [d : (U #f .↓)] [v? : (U #f Integer)] [l^3 : Symbol^3])
  ; contract stuff
  (struct .μc/κ [x : Symbol])
  (struct .λc/κ [c : (Listof .e)] [c↓ : (Listof .V)] [d : .e] [ρ : .ρ] [v? : Boolean])
  (struct .structc/κ [t : Symbol] [c : (Listof .e)] [ρ : .ρ] [c↓ : (Listof .V)])
  ; magics for termination
  (struct .rt/κ [σ : .σ] [f : .λ↓] [x : (Listof .V)])
  (struct .blr/κ [F : .F] [σ : .σ] [v : .V])
  (struct .recchk/κ [c : .μ/C] [v : .V]) ; where all labels are fully resolved
  ; experiment
  (struct .μ/κ [F : .μ/V] [xs : (Listof .V)] [σ : .σ]))
(define-type .κ* (Listof .κ))

; ctx in e's position for pending states
(struct .ς ([e : (U (Pairof .rt/κ .F) .E)] [s : .σ] [k : .κ*]) #:transparent)
(define-type .ς+ (Setof .ς))
(define-type .ς* (U .ς .ς+))

(: final? : .ς → Boolean)
(define (final? ς)
  (match? ς (.ς (? .blm?) _ _) (.ς (? .V?) _ (list))))

(: inj : .e → .ς)
(define (inj e)
  (.ς (.↓ e ρ∅) σ∅ empty))

(define-type .K (List .F .σ .κ* .κ*))
(define-type .res (List .σ .V))

(: ev : .p → .ς+)
(define (ev p)
  (log-info "called `ev` in machine.rkt ... ~a" (current-process-milliseconds))

  (match-define (.p (and m* (.m* _ ms)) _ e) p)
  (define step (step-p m*))
  (define Ξ : (MMap .rt/κ .K) (make-hash))
  (define M : (MMap .rt/κ .res) (make-hash))

  (: Ξ+! : .rt/κ .K → Void)
  (define (Ξ+! ctx K)
    #;(log-debug "Ξ[~a] += ~a~n~n"
              (show-κ σ ctx)
              `((σ: ,@(show-σ σ))
                (l: ,@(show-k σ l))
                (r: ,@(show-k σ r))))
    (mmap-join! Ξ ctx K))

  (: M+! : .rt/κ .res → Void)
  (define (M+! ctx res)
    #;(log-debug "abt to add:~nres:~n~a~nctx:~n~a~n~n" res ctx)
    (match-define (list σ V) res)
    (define res* (hash-ref M ctx (λ () ∅)))
    (define del
      (for/fold ([del : (Setof .res) ∅]) ([r : .res res*])
        (match-define (list σ0 V0) r)
        #;(log-debug "Comparing:~nV0:~n~a~nσ0:~n~a~nV1:~n~a~nσ1:~n~a~n~n" V0 σ0 V σ)
        #;(log-debug "Result: ~a ~a~n~n" ((⊑ σ σ0) V V0) ((⊑ σ0 σ) V0 V))
        (cond
         [((⊑ σ σ0) V V0) (set-add del (list σ V))]
         [((⊑ σ0 σ) V0 V) (set-add del (list σ0 V0))]
         [else del])))
    #;(log-debug "old-res for:~n~a~n~n~a~n~n" (set-count res*))
    #;(log-debug ",")
    (hash-set! M ctx (set-subtract (set-add res* (list σ V)) del)))

  (: upd-M! : .rt/κ .res .res → Void)
  (define (upd-M! ctx res0 resi)
    (hash-update! M ctx (λ ([s : (Setof .res)])
                          (set-add (set-remove s res0) resi))))

  (: Ξ@ : .rt/κ → (Listof .K))
  (define (Ξ@ ctx) (set->list (hash-ref Ξ ctx (λ () ∅))))

  (: M@ : .rt/κ → (Listof .res))
  (define (M@ ctx) (set->list (hash-ref M ctx (λ () ∅))))

  (: m-opaque? : Symbol → Boolean)
  (define (m-opaque? x) ; TODO: expensive?
    (match-define (.m _ defs) (hash-ref ms x))
    (for/or ([d (in-hash-values defs)] #:when (match? d (cons '• _))) #t))

  (: step* : .ς → .ς+)
  (define (step* ς)
    (define-set ans : .ς)
    (define-set seen : .ς)

    (: resume : .res .K .rt/κ → Void)
    ; ans: the answer to plug in
    ; ctx: pending context
    ; rt: which context to return to
    (define (resume ans ctx rt)
      (match-define (list σ₀ V₀) ans)
      (match-define (list F σₖ kₗ kᵣ) ctx)
      ; avoid bogus branches
      (when (for/and : Any ([(i j) (in-hash F)])
              (and (or ((⊑ σ₀ σₖ) (σ@ σ₀ i) (σ@ σₖ j))
                       ((⊑ σₖ σ₀) (σ@ σₖ j) (σ@ σ₀ i)))
                   #t #|just to force boolean|#))
        (define k (append kₗ (list* (.blr/κ F σ₀ V₀) rt kᵣ)))
        (define-values (σₖ′ F′)
          (for/fold ([σ : .σ σₖ] [F : .F F]) ([i (in-hash-keys F)])
            (match-define (list σ′ _ F′) (transfer σ₀ (.L i) σ F))
            (values σ′ F′)))
        (match-define (list σₖ′′ V-new _) (transfer σ₀ V₀ σₖ′ F′))
        (define ς (.ς V-new σₖ′′ k))
        (define ς^ (canon ς))
        (visit ς)))

    (define-syntax-rule (memoizing ς e ...)
      (begin
        (define ς^ (canon ς))
        (when (seen-has? ς^)
          (log-debug "--SEEN BEFORE AS~n~a~n~n" (show-ς ς^)))
        (unless (seen-has? ς^)
          (log-debug "--REMEMBERED AS~n~a~n~n" (show-ς ς^))
          (seen-add! ς^)
          e ...)))

    ; imperative DFS speeds interpreter up by ~40%
    ; from not maintaining an explicit frontier set
    (: visit : .ς → Void)
    (define i 0)
    (define (visit ς)
      (log-debug "~a. visit: ~a~n|M|: ~a~n|Ξ|: ~a~n~n"
                 (begin0 i (set! i (+ 1 i))) (show-ς ς)
                 (show-count M)
                 (show-count Ξ))
      (match ς
        ; record final states, omit blames on top, havoc, and opaque modules
        [(? final? ς)
         (log-debug "--FINAL~n")
         (unless (match? ς (.ς [.blm (or '† '☠ (? m-opaque?)) _ _ _] _ _))
           (log-debug "--ADDED~n")
           (ans-add! ς))]
        ; remember waiting context and plug any available answers into it
        [(.ς (cons ctx F) σ k)
         (define-values (kₗ kᵣ) (split-κ* ctx k))
         (define K (list F σ kₗ kᵣ))
         (Ξ+! ctx K)
         (log-debug "--ADDED CONTEXT~n")
         (when (empty? (M@ ctx))
           (log-debug "--NO RESULT TO RESUME FOR NOW~n"))
         (for ([res : .res (M@ ctx)] [i (in-naturals 1)])
           (log-debug "--FOLLOW ONE OLD RESULT (~a/~a) :~n" i (length (M@ ctx)))
           (resume res K ctx))]
        ; remember returned value and return to any other waiting contexts
        [(.ς (? .V? V) σ (cons (? .rt/κ? ctx) k))
         (memoizing ς
           (define res (list σ V))
           (M+! ctx res)
           (log-debug "--ADDED RESULT~n")
           (for ([K : .K (Ξ@ ctx)] [i (in-naturals 1)])
             (log-debug "--RESUME ONE OLD CONTEXT (~a/~a) :~n" i (length (Ξ@ ctx)))
             (resume res K ctx))
           (log-debug "--FOLLOW MAIN PATH:~n")
           (visit (.ς V σ k)))]
        ; blur value in M table ; TODO: this is a hack
        [(.ς (? .V? V) σ (list* (.blr/κ F σ0 V0) (? .rt/κ? ctx) k))
         (memoizing ς
           (match-define (cons σ′ Vi) (⊕ σ0 V0 σ V))
           (define σi (⊕ σ0 σ′ F))
           (define res0 (list σ0 V0))
           (define resi (list σi Vi))
           (when ((⊑ σ0 σi) V0 Vi)
             (log-debug "--BLUR RESULT~n")
             (upd-M! ctx res0 resi))
           (for ([K : .K (Ξ@ ctx)] [i (in-naturals 1)])
             (log-debug "--RESUME ONE OLD CONTEXT (~a/~a) :~n" i (length (Ξ@ ctx)))
             (resume resi K ctx))
           (log-debug "--FOLLOW MAIN PATH:~n")
           (visit (.ς V σ k)))]
        ; FIXME HACK
        [(.ς (? .V? V) σ (list* (.blr/κ F1 σ1 V1) (.blr/κ F0 σ0 V0) k))
         #;(log-debug "B: ~a  ⊕  ~a  =  ~a~n~n" (show-V σ V0) (show-V σ V1) (show-V σ (⊕ V0 V1)))
         #;(log-debug "Blur: ~a with ~a~n~n" (show-E σ V0) (show-E σ V1))
         (match-define (cons σ′ Vi) (⊕ σ0 V0 σ1 V1))
         (define σi (⊕ σ0 σ′ F0))
         (visit (.ς V σ (cons (.blr/κ F1 σi Vi) k)))]
        ; FIXME hack
        [(.ς (? .V?) _ (cons (? .recchk/κ?) _))
         (memoizing ς
           (match (step ς)
             [(? set? s) (for ([ςi s]) (visit ςi))]
             [(? .ς? ςi) (visit ςi)]))]
        ; FIXME hack
        [(.ς (.↓ (.@-havoc x) ρ) σ _)
         #;(log-debug "havoc ~a~n" (show-V σ (ρ@ ρ x)))
         (memoizing ς
           (match (step ς)
             [(? set? s) (for ([ςᵢ (in-set s)]) (visit ςᵢ))]
             [(? .ς? ς′) (visit ς′)]))]
        ; FIXME hack
        [(? ς-apply?)
         (memoizing ς
           (match (step ς)
             [(? set? s) (for ([ςᵢ (in-set s)]) (visit ςᵢ))]
             [(? .ς? ς′) (visit ς′)]))]
        ; do regular 1-step on unseen state
        [_ (match (dbg/off 'step (step ς))
             [(? set? s) (for ([ςi (in-set s)]) (visit ςi))]
             [(? .ς? ςi) (visit ςi)])]))

    ;; "main"
    (visit ς)
    (log-debug "#states: ~a, ~a base cases, ~a contexts~n~n"
               (set-count seen)
               (show-count M)
               (show-count Ξ))
    (log-debug "contexts:~n~a~n~n" (show-Ξ Ξ))
    (log-debug "results:~n~a~n~n" (show-M M))
    ans)

  (step* (inj e)))

(define-syntax-rule (match/nd v [p e ...] ...) (match/nd: (.Ans → .ς) v [p e ...] ...))
(: step-p : .m* → (.ς → .ς*))
(define (step-p m*)
  (match-define (.m* _ ms) m*)

  (: ref-e : Symbol Symbol → .e)
  (define (ref-e m x)
    (match-define (.m _ defs) (hash-ref ms m))
    (car (hash-ref defs x)))

  (: ref-c : Symbol Symbol → .e)
  (define (ref-c m x)
    (match-define (.m _ decs) (hash-ref ms m))
    (match (cdr (hash-ref decs x))
      [(? .e? c) c]
      [_ (error 'ref-c "module ~a does not export ~a" m x)]))

  (define HAVOC (match-let ([(? .λ? v) (ref-e '☠ 'havoc)]) (→V (.λ↓ v ρ∅))))

  (: havoc : .V .σ .κ* → .ς+)
  (define (havoc V σ k)
    (match (step-@ HAVOC (list V) '☠ σ '())
      [(? set? s) s]
      [(? .ς? ς) (set ς)]))

  (: step-β : .λ↓ (Listof .V) Symbol .σ .κ* → .ς)
  (define (step-β f Vx l σ k)
    #;(log-debug "Stepping ~a~n~n" (show-U σ f))
    (match-define (.λ↓ (.λ n e v?) ρ) f)
    (match v?
      [#f
       (cond
         [(= (length Vx) n)
          (define seens (apps-seen k σ f Vx))
          #;(log-debug "Chain:~n~a~n~n" seens)
          (or
           (for/or : (U #f .ς) ([res : (Pairof .rt/κ (Option .F)) seens]
                                #:when (.F? (cdr res)))
             (match-define (cons ctx (? .F? F)) res)
             #;(log-debug "Seen, repeated:~nold:~n~a~nNew:~n~a~nF: ~a~n~n" ctx (show-V σ Vx) F)
             (.ς (cons ctx F) σ k))
           (for/or : (U #f .ς) ([res : (Pairof .rt/κ (Option .F)) seens]
                                #:when (false? (cdr res)))
             #;(log-debug "Function: ~a~n~n" (show-U σ f))
             #;(log-debug "Seen, new~n")
             (match-define (cons (.rt/κ σ0 _ Vx0) _) res)
             (match-define (cons σ1 Vx1) (⊕ σ0 Vx0 σ Vx))
             #;(log-debug "Approx:~n~a~n~n" #;(cons Vx1 σ1) (show-V σ1 Vx1))
             (.ς (.↓ e (ρ++ ρ Vx1)) σ1 (cons (.rt/κ σ1 f Vx1) k)))
           (.ς (.↓ e (ρ++ ρ Vx)) σ (cons (.rt/κ σ f Vx) k)))]
         [else (.ς (.blm l 'Λ (Prim (length Vx)) (arity=/C n)) σ k)])]
      [#t (cond [(>= (length Vx) (- n 1)) ; FIXME varargs not handled yet
                 (.ς (.↓ e (ρ++ ρ Vx (- n 1))) σ k)]
                [else (.ς (.blm l 'Λ (Prim (length Vx)) (arity≥/C (- n 1))) σ k)])]))

  (: step-@ : .V (Listof .V) Symbol .σ .κ* → .ς*)
  (define (step-@ Vf V* l σ k)
    #;(log-debug "step-@:~n~a~n~a~n~n" (show-Ans σ Vf) (map (curry show-E σ) V*)) ;TODO reenable
    #;(log-debug "step-@:~nσ:~n~a~nf:~n~a~nx:~n~a~n~n" σ Vf V*)
    (match Vf
      [(.// U C*)
       (match U
         [(? .o? o) (match/nd (dbg/off '@ (δ σ o V* l)) [(cons σa A) (.ς A σa k)])]
         [(? .λ↓? f) (step-β f V* l σ k)]
         [(.Ar (.// (.Λ/C C* D v?) _) Vg (and l^3 (list _ _ lo)))
          (define V# (length V*))
          (define C# (length C*))
          (define n (if v? (- C# 1) #f))
          (cond
            [(if v? (>= V# (- C# 1)) (= V# C#))
             (.ς Vg σ (cons (.indy/κ C* V* '() D n l^3) k))]
            [else
             (.ς (.blm l lo (Prim (length V*))(if v? (arity≥/C (- C# 1)) (arity=/C C#))) σ k)])]
         [_
          (match/nd (δ σ 'procedure? (list Vf) 'Λ)
            [(cons σt (.// (.b #t) _)) (error 'Internal "step-@: impossible: ~a" (show-V σ Vf))]
            [(cons σf (.// (.b #f) _)) (.ς (.blm l 'Λ Vf PROC/C) σf k)])])]
      [(and L (.L i))
       (match/nd (δ σ 'procedure? (list L) 'Λ)
         [(cons σt (.// (.b #t) _))
          (match/nd (δ σt 'arity-includes? (list L (Prim (length V*))) 'Λ)
            [(cons σt (.// (.b #t) _))
             (match (σ@ σt i)
               [(and V (or (.// (? .λ↓?) _) (.// (? .Ar?) _))) (step-@ V V* l σt k)]
               [(? .μ/V? Vf)
                (define seens (μs-seen k σt Vf V*))
                (or
                 (for/or : (U #f .ς+) ([seen seens] #:when (hash? seen)) ∅)
                 (for/or : (U #f .ς*) ([seen seens] #:when (cons? seen))
                   (match-define (cons σ0 Vx0) seen)
                   (match-define (cons σi Vxi) (⊕ σ0 Vx0 σt V*))
                   (match/nd: (.V → .ς) (unroll Vf)
                     [Vj
                      (match-define (cons σi′ Vj′) (alloc σi Vj))
                      (step-@ Vj′ Vxi l σi′ (cons (.μ/κ Vf Vxi σi) k))]))
                 (match/nd: (.V → .ς) (unroll Vf)
                   [Vj
                    (match-define (cons σi Vj′) (alloc σt Vj))
                    #;(log-debug "0: ~a~n1: ~a~n~n" (show-V σ0 Vx0) (show-V σt V*))
                    (step-@ Vj′ V* l σi (cons (.μ/κ Vf V* σt) k))]))]
               [_
                (define havocs
                  (for/fold ([s : (Setof .ς) ∅]) ([V V*])
                    (set-union s (havoc V σt '()))))
                (define-values (σ′ La) (σ+ σt))
                (set-add havocs (.ς La σ′ k))])]
            [(cons σf (.// (.b #f) _)) (.ς (.blm l 'Λ Vf (arity-includes/C (length V*))) σf k)])]
         [(cons σf (.// (.b #f) _)) (.ς (.blm l 'Λ Vf PROC/C) σf k)])]))

  (: step-fc : .V .V Symbol .σ .κ* → .ς*)
  (define (step-fc C V l σ k)
    (match (⊢ σ V C)
      ['Proved (.ς TT σ k)]
      ['Refuted (.ς FF σ k)]
      ['Neither
       (match C
         [(.// U D*)
          (match U
            [(and (.μ/C x C′) U)
             (cond
               [(chk-seen? k U (V-abs σ V))
                (match-define (cons σ′ _) (refine σ V C))
                (.ς TT σ′ k)]
               [else
                (match-define (cons σt _) (refine σ V C))
                (match-define (cons σf _) (refine σ V (.¬/C C)))
                {set (.ς TT σt k) (.ς FF σf k)}])]
            [(.St 'and/c (list C1 C2)) (and/ς (list (.FC C1 V l) (.FC C2 V l)) σ k)]
            [(.St 'or/c (list C1 C2)) (or/ς (list (.FC C1 V l) (.FC C2 V l)) σ k)]
            [(.St '¬/c (list C′)) (.ς (.FC C′ V l) σ (cons (.@/κ '() (list (Prim 'not)) l) k))]
            [(.St/C t C*)
             (match/nd (δ σ (.st-p t (length C*)) (list V) l)
               [(cons σt (.// (.b #t) _))
                (match-define (.// (.St t V*) _) (σ@ σt V))
                (and/ς (for/list ([Vi V*] [Ci C*]) (.FC Ci Vi l)) σ k)]
               [(cons σf (.// (.b #f) _)) (.ς FF σf k)])]
            [_ (step-@ C (list V) l σ k)])]
         [(.L _) (step-@ C (list V) l σ k)])]))

  (: step-▹ : .V .V Symbol^3 .σ .κ* → .ς*)
  (define (step-▹ C V l^3 σ k)
    #;(log-debug "Mon:~nC:~a~nV:~a~nσ:~a~nk:~a~n~n" C V σ k)
    (match-define (list l+ l- lo) l^3)
    (match (⊢ σ V C) ; want a check here to reduce redundant cases for recursive contracts
      ['Proved (.ς V σ k)]
      ['Refuted (.ς (.blm l+ lo V C) σ k)]
      ['Neither
       (match C
         [(.L i)
          (match-define (cons σt Vt) (refine σ V C))
          (match-define (cons σf Vf) (refine σ V (.¬/C C)))
          {set (.ς Vt σt k) (.ς Vf σf k)}]
         [(.// Uc C*)
          (match Uc
            [(and (.μ/C x C′) Uc)
             (cond
               [(chk-seen? k Uc (V-abs σ V))
                (match-define (cons σ′ V′) (dbg/off 'ho (refine σ V C)))
                (.ς V′ σ′ k)]
               ; hack to speed things up
               [(flat/C? σ C)
                #;(log-debug "Abt to refine:~nσ:~n~a~nV:~n~a~nC:~n~a~n~n" σ V C)
                (match-define (cons σt Vt) (refine σ V C))
                (match-define (cons σf _) (refine σ V (.¬/C C)))
                {set (.ς Vt σt k) (.ς (.blm l+ lo V C) σf k)}]
               [else (.ς V σ (list* (.▹/κ (cons (unroll/C Uc) #f) l^3) (.recchk/κ Uc (V-abs σ V)) k))])]
            [(.St 'and/c (list Dl Dr)) (.ς V σ (▹/κ1 Dl l^3 (▹/κ1 Dr l^3 k)))]
            [(.St 'or/c (list Dl Dr))
             (.ς (.FC Dl V lo) σ (cons (.if/κ (.Assume V Dl) (.Mon Dr V l^3)) k))]
            [(.St '¬/c (list D))
             (.ς (.FC D V lo) σ (cons (.if/κ (.blm l+ lo V C) (.Assume V C)) k))]
            [(.St/C t C*)
             (define n (length C*))
             (match/nd (δ σ (.st-p t n) (list V) lo)
               [(cons σt (.// (.b #t) _))
                (match-define (.// (.St t V*) _) (dbg/off '▹ (σ@ σt V)))
                (.ς (→V (.st-mk t n)) σt
                    (cons (.@/κ (for/list ([C C*] [V V*]) (.Mon C V l^3)) '() lo) k))]
               [(cons σf (.// (.b #f) _)) (.ς (.blm l+ lo V (→V (.st-p t n))) σf k)])]
            [(and Uc (.Λ/C Cx* D v?))
             (match/nd (δ σ 'procedure? (list V) lo)
               [(cons σt (.// (.b #t) _))
                (match v?
                  [#f (match/nd (δ σt 'arity-includes? (list V (Prim (length Cx*))) lo)
                        [(cons σt (.// (.b #t) _)) (.ς (→V (.Ar C V l^3)) σt k)]
                        [(cons σf (.// (.b #f) _)) (.ς (.blm l+ lo V (arity-includes/C (length Cx*))) σf k)])]
                  [#t (match/nd (δ σt 'arity>=? (list V (Prim (- (length Cx*) 1))) lo)
                        [(cons σt (.// (.b #t) _)) (.ς (→V (.Ar C V l^3)) σt k)]
                        [(cons σf (.// (.b #f) _)) (.ς (.blm l+ lo V (arity≥/C (- (length Cx*) 1))) σf k)])])]
               [(cons σf (.// (.b #f) _)) (.ς (.blm l+ lo V PROC/C) σf k)])]
            [_ (.ς (.FC C V lo) σ (cons (.if/κ (.Assume V C) (.blm l+ lo V C)) k))])])]))

  (: step-E : .E .σ .κ* → .ς*)
  (define (step-E E σ k)
    #;(log-debug "E: ~a~n~n" E)
    (match E
      [(.↓ e ρ)
       (match e
         [(? .•?) (let-values ([(σ′ L) (σ+ σ)]) (.ς L σ′ k))]
         [(? .v? v) (.ς (close v ρ) σ k)]
         [(.x sd) (when (.X/V? (ρ@ ρ sd)) (error 'Internal "step-E")) (.ς (ρ@ ρ sd) σ k)]
         [(.x/c x) (.ς (ρ@ ρ x) σ k)]
         [(.ref name ctx ctx) (.ς (.↓ (ref-e ctx name) ρ∅) σ k)]
         [(.ref name in ctx)
          (.ς (.↓ (ref-c in name) ρ∅) σ
              (cons (.▹/κ  (cons #f (.↓ (ref-e in name) ρ∅)) (list in ctx in)) k))]
         [(.@ f xs l) (.ς (.↓ f ρ) σ (cons (.@/κ (for/list ([x xs]) (.↓ x ρ)) '() l) k))]
         [(.@-havoc x)
          (define V
            (match (ρ@ ρ x)
              [(? .//? V) V]
              [(.L i) (match (σ@ σ i)
                        [(? .//? V) V]
                        [(? .μ/V? V) (unroll V)])]
              [(? .μ/V? V) (unroll V)]))
          (match/nd: (.V → .ς) V
            [(and V (.// U C*))
             ; always alloc the result of unroll
             ; FIXME: rewrite 'unroll' to force it
             (match-define (cons σ′ V′) (alloc σ V))
             #;(log-debug "havoc: ~a~n~n" (show-V σ′ V′))
             (match U
               [(.λ↓ (.λ n _ _) _)
                (define-values (σ′′ Ls) (σ++ σ′ n))
                (step-@ V′ Ls '☠ σ′′ k)]
               [(.Ar (.// (.Λ/C Cx _ _) _) _ _)
                (define-values (σ′′ Ls) (σ++ σ′ (length Cx)))
                (step-@ V′ Ls '☠ σ′′ k)]
               [_ ∅])]
            [X (error 'Internal "@-havoc: ~a" X)])]
         [(.if i t e) (.ς (.↓ i ρ) σ (cons (.if/κ (.↓ t ρ) (.↓ e ρ)) k))]
         [(.amb e*) (for/set: .ς ([e e*]) (.ς (.↓ e ρ) σ k))]
         [(.μ/c x e) (.ς (.↓ e (ρ+ ρ x (→V (.X/C x)))) σ (cons (.μc/κ x) k))]
         [(.λ/c '() d v?) (.ς (→V (.Λ/C '() (.↓ d ρ) v?)) σ k)]
         [(.λ/c (cons c c*) d v?) (.ς (.↓ c ρ) σ (cons (.λc/κ c* '() d ρ v?) k))]
         [(.struct/c t '()) (.ς (→V (.st-p t 0)) σ k)]
         [(.struct/c t (cons c c*)) (.ς (.↓ c ρ) σ (cons (.structc/κ t c* ρ '()) k))])]
      [(.Mon C E l^3) (.ς C σ (cons (.▹/κ (cons #f E) l^3) k))]
      [(.FC C V l) (step-fc C V l σ k)]
      [(.Assume V C) (match-let ([(cons σ′ V′) (refine σ V C)]) (.ς V′ σ′ k))]))

  (: step-V : .V .σ .κ .κ* → .ς*)
  (define (step-V V σ κ k)
    (match κ
      [(.if/κ E1 E2)
       (match/nd (δ σ 'false? (list V) 'Λ)
         [(cons σt (.// (.b #f) _)) (.ς E1 σt k)]
         [(cons σf (.// (.b #t) _)) (.ς E2 σf k)])]

      [(.@/κ (cons E1 Er) V* l) (.ς E1 σ (cons (.@/κ Er (cons V V*) l) k))]
      [(.@/κ '() V* l)
       (match-define (cons Vf Vx*) (reverse (cons V V*)))
       (step-@ Vf Vx* l σ k)]

      [(.▹/κ (cons #f (? .E? E)) l^3) (.ς E σ (cons (.▹/κ (cons V #f) l^3) k))]
      [(.▹/κ (cons (? .V? C) #f) l^3) (step-▹ C V l^3 σ k)]

      [(.rt/κ _ _ _) (.ς V σ k)]
      [(.recchk/κ _ _) (.ς V σ k)]
      [(.μ/κ _ _ _) (.ς V σ k)]

      ;; indy
      [(.indy/κ (list Ci) (cons Vi Vr) Vs↓ D n l^3) ; repeat last contract, handling var-args
       (step-▹ Ci Vi (¬l l^3) σ (cons (.indy/κ (list Ci) Vr (cons V Vs↓) D n l^3) k))]
      [(.indy/κ (cons Ci Cr) (cons Vi Vr) Vs↓ D n l^3)
       (step-▹ Ci Vi (¬l l^3) σ (cons (.indy/κ Cr Vr (cons V Vs↓) D n l^3) k))]
      [(.indy/κ _ '() Vs↓ (.↓ d ρ) n l^3) ; evaluate range contract
       (match-define (and V* (cons Vf Vx*)) (reverse (cons V Vs↓)))
       (.ς (.↓ d (ρ++ ρ Vx* n)) σ (cons (.indy/κ '() '() V* #f n l^3) k))]
      [(.indy/κ _ '() (cons Vf Vx) #f _ (and l^3 (list l+ _ _))) ; apply inner function
       #;(log-debug "range: ~a~n~n" (show-E σ V))
       (step-@ Vf Vx l+ σ (▹/κ1 V l^3 k))]

      ; contracts
      [(.μc/κ x) (.ς (→V (.μ/C x V)) σ k)]
      [(.λc/κ '() c↓ d ρ v?) (.ς (→V (.Λ/C (reverse (cons V c↓)) (.↓ d ρ) v?)) σ k)]
      [(.λc/κ (cons c c*) c↓ d ρ v?) (.ς (.↓ c ρ) σ (cons (.λc/κ c* (cons V c↓) d ρ v?) k))]
      [(.structc/κ t '() _ c↓) (.ς (→V (.St/C t (reverse (cons V c↓)))) σ k)]
      [(.structc/κ t (cons c c*) ρ c↓) (.ς (.↓ c ρ) σ (cons (.structc/κ t c* ρ (cons V c↓)) k))]))

  (match-lambda
    [(.ς (? .V? V) σ (cons κ k))
     (when (match? V (.// '• _))
       (error 'Internal "step-p: impossible ~a" (show-ς (.ς V σ (cons κ k)))))
     (step-V V σ κ k)]
    [(.ς (? .E? E) σ k) (step-E E σ k)]))

(: and/ς : (Listof .E) .σ .κ* → .ς)
(define (and/ς E* σ k)
  (match E*
    ['() (.ς TT σ k)]
    [(list E) (.ς E σ k)]
    [(cons E Er) (.ς E σ (foldr (λ ([Ei : .E] [k : .κ*]) (cons (.if/κ Ei FF) k)) k Er))]))

(: or/ς : (Listof .E) .σ .κ* → .ς)
(define (or/ς E* σ k)
  (match E*
    ['() (.ς FF σ k)]
    [(list E) (.ς E σ k)]
    [(cons E Er) (.ς E σ (foldr (λ ([Ei : .E] [k : .κ*]) (cons (.if/κ TT Ei) k)) k Er))]))

(: ▹/κ1 : .V Symbol^3 .κ* → .κ*)
(define (▹/κ1 C l^3 k)
  (match C
    [(.// (.λ↓ (.λ 1 (.b #t) _) _) _) k]
    [(.// (? .Λ/C?) _) (cons (.▹/κ (cons C #f) l^3) k)]
    [_ (cons (.▹/κ (cons C #f) l^3)
             (let trim : .κ* ([k : .κ* k])
               (match k
                 [(cons (and κ (.▹/κ (cons (? .V? D) #f) _)) kr)
                  (match (C⇒C C D)
                    ['Proved (trim kr)]
                    [_ (cons κ (trim kr))])]
                 [_ k])))]))

(: apps-seen : .κ* .σ .λ↓ (Listof .V) → (Listof (Pairof .rt/κ (Option .F))))
(define (apps-seen k σ f Vx)
  #;(log-debug "apps-seen~nf: ~a~nk: ~a~n~n" (show-V σ∅ (→V f)) (show-k σ∅ k))
  (for/fold ([acc : (Listof (Pairof .rt/κ (Option .F))) '()]) ([κ k])
    (match κ
      [(and κ (.rt/κ σ0 f0 Vx0))
       (cond [(equal? f0 f)
              (cons (ann (cons κ ((⊑ σ σ0) Vx Vx0))
                         (Pairof .rt/κ (Option .F)))
                    acc)]
             [else acc])]
      [_ acc])))

(: μs-seen : .κ* .σ .μ/V (Listof .V) → (Listof (U .F (Pairof .σ (Listof .V)))))
(define (μs-seen k σ f Vx)
  #;(log-debug "apps-seen~nf: ~a~nk: ~a~n~n" (show-V σ∅ (→V f)) (show-k σ∅ k))
  (for/fold ([acc : (Listof (U .F (Pairof .σ (Listof .V)))) '()]) ([κ k])
    (match κ
      [(.μ/κ g Vx0 σ0)
       (match ((⊑ σ σ0) Vx Vx0)
         [#f (cons (ann (cons σ0 Vx0) (Pairof .σ (Listof .V))) acc)]
         [(? hash? F) (cons F acc)])]
      [_ acc])))

(: split-κ* : .rt/κ .κ* → (Values .κ* .κ*))
(define (split-κ* κ k)
  #;(log-debug "Split:~n~a~n~n~a~n~n" κ k)
  (let go ([l : .κ* '()] [k k])
    (match k
      ['() (error 'Internal "split-κ* : empty stack")]
      [(cons (? .rt/κ? κ′) kr)
       (cond [(equal? κ κ′) (values (reverse l) kr)]
             [else (go (cons κ′ l) kr)])]
      [(cons κ kr) (go (cons κ l) kr)])))

(: chk-seen? : .κ* .μ/C .V → Boolean)
(define (chk-seen? k C V)
  (for/or ([κ k] #:when (match? κ (? .recchk/κ?)))
    (match-define (.recchk/κ C′ V′) κ)
    (and (equal? C′ C) (equal? V′ V))))

;; for debugging
(define (e x) (set->list (ev (read-p x))))

(: show-k : .σ .κ* → (Listof Any))
(define (show-k σ k) (for/list ([κ k]) (show-κ σ κ)))

(: show-κ : .σ .κ → Any)
(define (show-κ σ κ)
  (define E (curry show-E σ))
  (match κ
    [(.if/κ t e) `(if ∘ ,(E t) ,(E e))]
    [(.@/κ e* v* _) `(@ ,@(reverse (map E v*)) ∘ ,@(map E e*))]
    [(.▹/κ (cons #f (? .E? e)) _) `(∘ ▹ ,(E e))]
    [(.▹/κ (cons (? .E? C) #f) _) `(,(E C) ▹ ∘)]
    [(.indy/κ Cs xs xs↓ d _ _) `(indy ,(map E Cs) ,(map E xs) ,(map E xs↓)
                                      ,(match d [#f '_] [(? .E? d) (E d)]))]
    [(.μc/κ x) `(μ/c ,x ∘)]
    [(.λc/κ cs Cs d ρ _) `(λ/c (,@(reverse (map E Cs)) ,@(map (curry show-e σ) cs)) ,(show-e σ d))]
    [(.structc/κ t c _ c↓) `(struct/c ,t (,@(reverse (map E c↓)) ,(map (curry show-e σ) c)))]
    [(.rt/κ _ f x) `(rt ,(E (→V f)) ,@(map E x))]
    [(.blr/κ _ _ V) `(blr ,(E V))]
    [(.recchk/κ c v) `(μ/▹ ,(E (→V c)) ,(E v))]))

(: show-ς : .ς → Any)
(define show-ς
  (match-lambda
    [(.ς E σ k) `((E: ,(if (.E? E) (show-E σ E) (show-κ σ (car E))))
                  (σ: ,@(show-σ σ))
                  (k: ,@(show-k σ k)))]))

; rename all labels to some canonnical form based on the expression's shape
; relax, this only happens a few times, not that expensive
(: canon : .ς → .ς)
(define (canon ς)
  (match-define (.ς (? .E? E) σ k) ς)
  (define F F∅)
  (: alloc! : Integer → Integer)
  (define (alloc! i)
    (cond [(hash-ref F i #f)]
          [else
           (define j (hash-count F))
           (set! F (hash-set F i j))
           j]))

  (: go! : (case→ [.V → .V] [.↓ → .↓] [.E → .E]
                  [.μ/C → .μ/C] [.λ↓ → .λ↓] [.U → .U] [.ρ → .ρ] [.κ → .κ] [.κ* → .κ*]
                  [(Listof .V) → (Listof .V)] [(Listof .E) → (Listof .E)]
                  [.σ → .σ]))
  (define (go! x)
    (match x
      ; E
      [(.↓ e ρ) (.↓ e (go! ρ))]
      [(.FC C V ctx) (.FC (go! C) (go! V) ctx)]
      [(.Mon C E l) (.Mon (go! C) (go! E) l)]
      [(.Assume V C) (.Assume (go! V) (go! C))]
      [(.blm f g V C) (.blm f g (go! V) (go! C))]
      ; V
      [(.L i) (.L (alloc! i))]
      [(.// U C*) (.// (go! U) C*)]
      [(? .μ/V? V) V]
      [(? .X/V? V) V]
      ; U
      [(.Ar C V l) (.Ar (go! C) (go! V) l)]
      [(.St t V*) (.St t (go! V*))]
      [(.λ↓ f ρ) (.λ↓ f (go! ρ))]
      [(.Λ/C C* D v?) (.Λ/C (go! C*) (go! D) v?)]
      [(.St/C t V*) (.St/C t (go! V*))]
      [(.μ/C x V) (.μ/C x (go! V))]
      [(? .X/C? x) x]
      [(? .prim? p) p]
      ; ρ
      [(.ρ m l) (.ρ (for/hash : (Map (U Integer Symbol) .V) ([(i V) (in-hash m)])
                      (values i (go! V)))
                    l)]
      ; κ
      [(.if/κ t e) (.if/κ (go! t) (go! e))]
      [(.@/κ e* v* l) (.@/κ (go! e*) (go! v*) l)]
      [(.▹/κ (cons C E) l)
       (.▹/κ (cond [(and (false? C) (.E? E)) (cons #f (go! E))]
                   [(and (.V? C) (false? E)) (cons (go! C) #f)]
                   [else (error 'Internal "go!: impossible!")])
             l)]
      [(.indy/κ c x x↓ d v? l)
       (.indy/κ (go! c) (go! x) (go! x↓) (if (.↓? d) (go! d) #f) v? l)]
      [(? .μc/κ? x) x]
      [(.λc/κ c c↓ d ρ v?) (.λc/κ c (go! c↓) d (go! ρ) v?)]
      [(.structc/κ t c ρ c↓) (.structc/κ t c (go! ρ) (go! c↓))]
      [(.rt/κ σ f x) (.rt/κ σ (go! f) (go! x))]
      #;[(.blr/κ G σ V) (.blr/κ (for/fold: ([G′ : .F G]) ([i (in-hash-keys G)])
                                (let ([j (alloc! i)]
                                      [k (alloc! (hash-ref G i))])
                                  (hash-set G′ j k)))
                              σ (go! V))]
      #;[(.recchk/κ C V) (.recchk/κ (go! C) (go! V))]
      [(.μ/κ f xs σ) (.μ/κ f (go! xs) σ)]
      ; list
      [(? list? l)
       (for/list ([i l] #:unless (or #;(.rt/κ? i) (.blr/κ? i) (.recchk/κ? i))) (go! i))]))

  (: fixup/V : .V → .V)
  (define fixup/V
    (match-lambda
     [(? .L? x) x]
     [(.// U Cs) (.// (fixup/U U) (subst/L Cs F))]
     [(.μ/V x V*) (.μ/V x (subst/L V* F))]
     [(? .X/V? x) x]))

  (: fixup/E : (case-> (.↓ → .↓) (.E → .E)))
  (define fixup/E
    (match-lambda
     [(.↓ e ρ) (.↓ e (fixup/ρ ρ))]
     [(.FC c v l) (.FC (fixup/V c) (fixup/V v) l)]
     [(.Mon c e l) (.Mon (fixup/E c) (fixup/E e) l)]
     [(.Assume v c) (.Assume (fixup/V v) (fixup/V c))]
     [(.blm f g v c)(.blm f g (fixup/V v) (fixup/V c))]
     [(? .V? V) (fixup/V V)]))

  (: fixup/U : (case-> [.μ/C → .μ/C] [.λ↓ → .λ↓] [.U → .U]))
  (define fixup/U
    (match-lambda
     [(.Ar c v l) (.Ar (fixup/V c) (fixup/V v) l)]
     [(.St t V*) (.St t (fixup/V* V*))]
     [(.λ↓ f ρ) (.λ↓ f (fixup/ρ ρ))]
     [(.Λ/C c d v?) (.Λ/C (fixup/V* c) (fixup/E d) v?)]
     [(.St/C t V*) (.St/C t (fixup/V* V*))]
     [(.μ/C x c) (.μ/C x (fixup/V c))]
     [(? .X/C? x) x]
     [(? .prim? p) p]))

  (: fixup/ρ : .ρ → .ρ)
  (define (fixup/ρ ρ)
    (match-define (.ρ m l) ρ)
    (.ρ (for/hash : (Map (U Integer Symbol) .V) ([(i V) (in-hash m)])
          (values i (fixup/V V)))
        l))

  (: fixup/κ : .κ → .κ)
  (define fixup/κ
    (match-lambda
     [(.if/κ t e) (.if/κ (fixup/E t) (fixup/E e))]
     [(.@/κ e* v* l) (.@/κ (fixup/E* e*) (fixup/V* v*) l)]
     [(.▹/κ (cons C E) l)
      (.▹/κ (cond [(and (false? C) (.E? E)) (cons #f (fixup/E E))]
                  [(and (.V? C) (false? E)) (cons (fixup/V C) #f)]
                  [else (error 'Internal "fixup/κ: impossible")])
            l)]
     [(.indy/κ c x x↓ d v? l)
      (.indy/κ (fixup/V* c) (fixup/V* x) (fixup/V* x↓) (if (.↓? d) (fixup/E d) #f) v? l)]
     [(? .μc/κ? x) x]
     [(.λc/κ c c↓ d ρ v?) (.λc/κ c (fixup/V* c↓) d (fixup/ρ ρ) v?)]
     [(.structc/κ t c ρ c↓) (.structc/κ t c (fixup/ρ ρ) (fixup/V* c↓))]
     [(.rt/κ σ f x) (.rt/κ (fixup/σ σ) (fixup/U f) (fixup/V* x))]
     #;[(.blr/κ G σ V) (.blr/κ G (fixup σ) (fixup V))]
     #;[(.recchk/κ C V) (.recchk/κ (fixup C) (fixup V))]
     [(.μ/κ f xs σ) (.μ/κ f (fixup/V* xs) (fixup/σ σ))]))

  (: fixup/κ* : .κ* → .κ*)
  (define (fixup/κ* κ*)
    (for/list : .κ* ([κ (in-list κ*)]
                     #:unless
                     (or #;(.rt/κ? κ) (.blr/κ? κ) (.recchk/κ? κ)))
      (fixup/κ κ)))

  (: fixup/σ : .σ → .σ)
  (define (fixup/σ σ)
    (match-define (.σ m _) σ)
    (define-values (σ′ _) (σ++ σ∅ (hash-count F)))
    (for/fold ([σ′ : .σ σ′]) ([i (in-hash-keys F)])
      (match (hash-ref m i #f)
        [(? .V? Vi) (σ-set σ′ (hash-ref F i) (subst/L Vi F))]
        [#f σ′])))

  (: fixup/E* : (Listof .E) → (Listof .E))
  (define (fixup/E* l) (map fixup/E l))

  (: fixup/V* : (Listof .V) → (Listof .V))
  (define (fixup/V* l) (map fixup/V l))

  (define E′ (go! E))
  (define k′ (go! k))
  (.ς (fixup/E E′) (fixup/σ σ) (fixup/κ* k′)))

(define (show-F [F : .F])
  (for/list : (Listof Any) ([(k v) (in-hash F)])
    `(,k ↦ ,v)))

(define (show-Ξ [Ξ : (MMap .rt/κ .K)])
  (for/list : (Listof Any) ([(ctx Ks) (in-hash Ξ)])
    `(,(show-κ σ∅ ctx)
      ↦
      ,(for/list : (Listof Any) ([K : .K (in-set Ks)])
         (match-define (list F σ kₗ kᵣ) K)
         `(,(show-F F) ,(show-σ σ) ,(show-k σ kₗ) ,(show-k σ kᵣ))))))

(define (show-M [M : (MMap .rt/κ .res)])
  (for/list : (Listof Any) ([(ctx reses) (in-hash M)])
    `(,(show-κ σ∅ ctx)
      ↦
      ,(for/list : (Listof Any) ([res : .res (in-set reses)])
         (match-define (list σ V) res)
         (show-Ans σ V)))))

(: show-count : (∀ (X Y) (MMap X Y) → (List Integer Integer)))
(define (show-count m)
  (list (hash-count m)
        (for/sum : Integer ([s (in-hash-values m)]) (set-count s))))

;; Recognize one "class" of states where a function is about to be applied
(define (ς-apply? ς)
  (match ς
    [(.ς (? .V?) _ (cons (.@/κ '() Vs _) _))
     (or (empty? Vs)
         (match? (last Vs) (.// (? .λ↓?) _)))]
    [_ #f]))