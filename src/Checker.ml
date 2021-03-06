(* Well-Formnedness Checker Functions *)
(* author: Yu-Yang Lin *)
(* Read notes for specification of each function *)
open AbstractSyntax
open StringFormats
open Helper
open AlphaEquivalence
open CongruenceClosure
open Format

(******** MODULE-SPECIFIC HELPER FUNCTIONS ********)
(* entails function for By rule, can become more powerful this way *)
let prop_entails a b = alpha_equiv_prop_result a b


(******************** CHECK AND INFER TERM FUNCTIONS ********************)
(* term type inference [notes: section 2 and 3], (psi |- t => tau) *)
let rec infer_term (psi : ctx) ((p,t) : term) :(tp result) =
  match t with
  | Zero      -> return Nat                                                              (*nat-zero*)
  | Suc (t')  -> (check_term psi t' Nat) >> (return Nat)                                 (*nat-suc-n*)
  | Var x     -> lookup_ctx_result psi x p                                               (*var*)
  | App (e,v) -> (infer_term psi e) >>=                                                  (*application*)
                   (function
                     | Arrow (a,b) -> (check_term psi v a) >> (return b)
                     | _           -> Wrong (term_not_function e v,p))
  | Boolean (true)  -> return Bool                                                       (*bool-true*)
  | Boolean (false) -> return Bool                                                       (*bool-false*)
  | Cons (v,v')     -> Wrong (cons_inference_error,p)                                    (*list-hd::tl*)
  | Nil             -> Wrong  (nil_inference_error,p)                                    (*list-empty*)
  | Pair (v,v')     -> Wrong  (nil_inference_error,p)                                    (*pairs*)

(* term type checking [notes: section 2 and 3], (psi |- t <= tau) *)
and check_term (psi : ctx) ((p,t) : term) (tau : tp) :(unit result) =
  match t , tau with
  | Cons (v,v') , List tau' -> (check_term psi v tau') >>                                (*list-hd::tl*)
                                 (check_term psi v' (List tau'))
  | Cons (v,v') , tau'      -> Wrong (term_not_of_type (p,t) tau',p)
  | Nil         , List tau' -> return ()                                                 (*list-empty*)
  | Nil         , tau'      -> Wrong (term_not_of_type (p,t) tau',p)
  | Pair (v,v') , PairType (t1,t2) -> (check_term psi v t1) >>                           (*pairs*)
                                        (check_term psi v' t2)
  | Pair (v,v') , tau'      -> Wrong (term_not_of_type (p,t) tau',p)
  | t'          , tau'      -> (infer_term psi (p,t')) >>=                               (*inference case*)
                                 (fun tau'' -> if tau'' = tau'
                                               then (return ())
                                               else Wrong (term_of_type (p,t) tau'' tau',p))

(* proposition type checking [notes: section 2 and 3] *)
let rec check_prop (psi : ctx) ((p,prop) : prop) :(unit result) =
  match prop with
  | Truth   -> return ()                                                                 (*top-prop*)
  | Falsity -> return ()                                                                 (*bot-prop*)
  | And (a,b)     -> (check_prop psi a) >> (check_prop psi b)                            (*and-prop*)
  | Or (a,b)      -> (check_prop psi a) >> (check_prop psi b)                            (*or-prop*)
  | Implies (a,b) -> (check_prop psi a) >> (check_prop psi b)                            (*implies-prop*)
  | Eq (t,t',tau) -> (check_term psi t tau) >> (check_term psi t' tau)                   (*eq-prop*)
  | Forall (x,tau,a) -> check_prop ((x,tau)::psi) a                                      (*forall-prop*)
  | Exists (x,tau,a) -> check_prop ((x,tau)::psi) a                                      (*exists-prop*)
  | PropVar x     -> (lookup_ctx_result psi x p) >>=
                       (fun t -> (match t with
                                  | Prop -> return ()
                                  | t    -> Wrong (not_Prop x t,p)))
  | TermProp t    -> (check_term psi t Prop)


(******************** APPLY SPINE FUNCTION ********************)
(* [notes: section 9.2] *)
let rec apply_spine (psi : ctx) (gamma : hyps) (s : spine) ((p,a) : prop) (spine_pos : pos_range) :(prop result) =
  match s , a with
  | []             , a                -> return (p,a)                                    (*id-spine-app*)
  | SpineH h :: s' , Implies (a,b)    -> (lookup_hyps_result gamma h p) >>=              (*implies-spine-app*)
                                           (fun a' -> (alpha_equiv_prop_result a a') >>
                                                        (apply_spine psi gamma s' b spine_pos))
  | SpineT t :: s' , Forall (x,tau,a) -> (check_term psi t tau) >>                       (*forall-spine-app*)
                                           (apply_spine psi gamma s' (subs_prop x t a) spine_pos)
  | sarg     :: s' , c                ->  Wrong (apply_spine_error sarg (p,a),spine_pos)


(******************** CHECK SIMPLE-PROOFS FUNCTION ********************)
(* [notes: section 9.1] *)
let rec check_spf ((pos,p) : pf) :(unit result) =
  match p with
  | TruthR         -> return ()
  | AndR (p,q)     -> (check_spf p) >> (check_spf q)
  | OrR1 p         -> check_spf p
  | OrR2 q         -> check_spf q
  | ByEq hs        -> return ()
  | Therefore (p,a)-> (check_spf p)
  | By h           -> return ()
  | SpineApp (h,s) -> return ()
  | Todo           -> return ()
  | _              -> (Wrong (not_simple_proof (pos,p),pos))


(******************** INSTANTIATE PROP VARS ********************)
let rec instantiate_var (xs : prop_instance) ((p,a) : prop) :(prop) =
  match xs with
  | []          -> (p,a)
  | (x,b) :: xs -> instantiate_var xs (subs_prop_var x b (p,a))


(******************** CHECK PROOF FUNCTION ********************)
(* proof type checking [notes: section 4, 5.1, 7, 8, 9] *)
let rec check_pf (psi : ctx) (gamma : hyps) ((pf_pos,proof) : pf) ((prop_pos,prop) : prop) :(unit result) =
  match proof , prop with
  | TruthR , Truth -> return ()                                                          (*TruthR*)
  | TruthR , _     -> (encountered_while "evaluating 'Truth' introduction")
                        (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | FalsityL h , _ -> (encountered_while "evaluating 'Falsity' elimination")             (*FalsityL/Absurd*)
                        ((lookup_hyps_result gamma h pf_pos) >>=
                           (function
                             | (pos,Falsity) -> return ()
                             | c             -> Wrong (hyp_of_type h c "Falsity",pf_pos)))
  | AndR (p,q) , And (a,b)  -> (encountered_while "evaluating 'and' introduction")       (*AndR*)
                                 ((check_pf psi gamma p a) >>
                                    (check_pf psi gamma q b))
  | AndR (p,q) , _          -> (encountered_while "evaluating 'and' introduction")
                                 (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | AndL (((h',a'),(h'',b')),h,p) , c -> (encountered_while "evaluating 'and' elimination")
                                           ((lookup_hyps_result gamma h pf_pos) >>=      (*AndL*)
                                              (function
                                                | (pos,And (a,b)) ->
                                                   (some_alpha_equiv_result a' a) >>
                                                     ((some_alpha_equiv_result b' b) >>
                                                        (check_pf psi ((h',a)::(h'',b)::gamma) p (prop_pos,c)))
                                                | d -> Wrong (hyp_of_type h d "'and' elimination",pf_pos)))
  | OrR1 p  , Or (a,b)         -> (encountered_while "evaluating 'or-left' introduction")(*OrR_1*)
                                    (check_pf psi gamma p a)
  | OrR1 p  , _                -> (encountered_while "evaluating 'or-left' introduction")
                                    (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | OrR2 q  , Or (a,b)         -> (encountered_while "evaluating 'or-right' introduction")
                                    (check_pf psi gamma q b)                             (*OrR_2*)
  | OrR2 q  , _                -> (encountered_while "evaluating 'or-right' introduction")
                                    (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | OrL (h,((h',a'),p),((h'',b'),q)) , c -> (encountered_while "evaluating 'or' elimination")
                                              (lookup_hyps_result gamma h pf_pos) >>=    (*OrL*)
                                              (function
                                                | (pos,Or (a,b)) ->
                                                   (some_alpha_equiv_result a' a) >>
                                                     ((some_alpha_equiv_result b' b) >>
                                                        ((check_pf psi ((h',a)::gamma) p (prop_pos,c)) >>
                                                           (check_pf psi ((h'',b)::gamma) q (prop_pos,c))))
                                                | d -> Wrong (hyp_of_type h d "'or' elimination",pf_pos))
  | ImpliesR ((h,a'),p)   , Implies (a,b) -> (encountered_while "evaluating '=>' introduction")
                                               ((some_alpha_equiv_result a' a) >>        (*ImpliesR*)
                                                  (check_pf psi ((h,a)::gamma) p b))
  | ImpliesR (h,p)        , _             -> (encountered_while "evaluating '=>' introduction")
                                               (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ImpliesL (p,((h',b'),h),q) , c        -> (encountered_while "evaluating '=>' elimination")
                                               ((lookup_hyps_result gamma h pf_pos) >>=  (*ImpliesL*)
                                                  (function
                                                    | (pos,Implies (a,b)) ->
                                                       (some_alpha_equiv_result b' b) >>
                                                         ((check_pf psi gamma p a) >>
                                                            (check_pf psi ((h',b)::gamma) q (prop_pos,c)))
                                                    | d -> Wrong (hyp_of_type h d "'=>' elimination",pf_pos)))
  | By h , b -> (encountered_while "evaluating 'by' clause")                             (*By*)
                  ((lookup_hyps_result gamma h pf_pos) >>=
                     (fun a -> prop_entails a (prop_pos,b)))
  | Therefore (p,a) , b -> (encountered_while "evaluating 'therefore' clause")           (*Therefore*)
                             ((alpha_equiv_prop_result a (prop_pos,b)) >>
                                (check_pf psi gamma p (prop_pos,b)))
  | ExistsR (t,p) , Exists (x,tau,a) -> (encountered_while "evaluating 'exists' introduction")
                                          ((check_term psi t tau) >>                     (*ExistsR*)
                                             (check_pf psi gamma p (subs_prop x t a)))
  | ExistsR _     , _                -> (encountered_while "evaluating 'exists' introduction")
                                          (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ExistsL ((y,(h',a')),h,p) , c    -> (encountered_while "evaluating 'exists' elimination")
                                          ((lookup_hyps_result gamma h pf_pos) >>=       (*ExistsL*)
                                             (function
                                               | (pos,Exists (x,tau,a)) ->
                                                  (some_alpha_equiv_result a' a) >>
                                                    (check_pf ((y,tau)::psi)
                                                              ((h',subs_prop x (prop_pos,Var y) a)::gamma)
                                                              p (prop_pos,c))
                                               | d -> Wrong (hyp_of_type h d "exists elim",pf_pos)))
  | ForallR ((y,tau),p) , Forall (x,tau',a) -> (encountered_while "evaluating 'forall' introduction")
                                                 (check_pf ((y,tau)::psi) gamma p        (*ForallR*)
                                                           (subs_prop x (prop_pos,Var y) a))
  | ForallR _           , _ -> (encountered_while "evaluating 'forall' introduction")
                                 (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ForallL ((h',a'),h,t,p)  , c -> (encountered_while "evaluating 'forall' elimination")
                                      ((lookup_hyps_result gamma h pf_pos) >>=
                                         (function
                                           | (pos,Forall (x,tau,a)) ->
                                              (some_alpha_equiv_result a' a) >>
                                                ((check_term psi t tau) >>
                                                   (check_pf psi ((h',subs_prop x t a)::gamma)
                                                             p (prop_pos,c)))
                                           | d -> Wrong (hyp_of_type h d "forall elim",pf_pos)))
  | ByIndNat  (p,(n,(h,a'),q)) , Forall (m,Nat,pred) ->                                  (*ByInd-Nat*)
     let pred_0     = subs_prop m (prop_pos,Zero)                 pred in
     let pred_n     = subs_prop m (prop_pos,Var n)                pred in
     let pred_suc_n = subs_prop m (prop_pos,Suc (prop_pos,Var n)) pred in
     (encountered_while "evaluating 'by induction on nat'")
       ((some_alpha_equiv_result a' pred_n) >>
          ((check_pf psi gamma p pred_0) >>
             (check_pf ((n,Nat)::psi) ((h,pred_n)::gamma) q pred_suc_n)))
  | ByIndNat _ , _ -> (encountered_while "evaluating 'by induction on nat'")
                        (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ByIndList (p,((x,xs),(h,a'),q)) , Forall (ys,List tau,pred) ->                       (*ByInd-List*)
     let pred_nil  = subs_prop ys (prop_pos,Nil)                                       pred in
     let pred_xs   = subs_prop ys (prop_pos,Var xs)                                    pred in (*IH*)
     let pred_x_xs = subs_prop ys (prop_pos,Cons ((prop_pos,Var x),(prop_pos,Var xs))) pred in
     (encountered_while "evaluating 'by induction on list'")
       ((some_alpha_equiv_result a' pred_xs) >>
          ((check_pf psi gamma p pred_nil) >>
             (check_pf ((x,tau)::(xs,List tau)::psi) ((h,pred_xs)::gamma) q pred_x_xs)))
  | ByIndList _ , _ -> (encountered_while "evaluating 'by induction on list'")
                         (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ByIndBool (p,q)     , Forall (b,Bool,pred) ->                                        (*ByInd-Bool*)
     (encountered_while "evaluating 'by induction on bool'")
       ((check_pf psi gamma p (subs_prop b (prop_pos,Boolean true) pred)) >>
          (check_pf psi gamma q (subs_prop b (prop_pos,Boolean false) pred)))
  | ByIndBool _ , _ -> (encountered_while "evaluating 'by induction on bool'")
                         (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | ByEq hs , Eq (t,t',tau) -> (encountered_while "evaluating 'by equality' clause")     (*ByEquality*)
                                 ((List.fold_right
                                     (fun h hs ->
                                      (lookup_hyps_result gamma h pf_pos) >>=
                                        (function
                                          | (pos,Eq (x,y,tau')) ->
                                             (match hs with
                                              | Ok hs -> return ((depos_term x,depos_term y)::hs)
                                              | Wrong (message,some_position) ->
                                                 if message = equality_error then return [(depos_term x,depos_term y)]
                                                 else Wrong (message,some_position))
                                          | d -> Wrong (hyp_not_eq h d tau,pf_pos))) hs
                                     (Wrong (equality_error,pf_pos))) >>=
                                    (fun e -> cong_entails_result e (depos_term t,depos_term t') pf_pos))
  | ByEq hs , _ -> (encountered_while "evaluating 'by equality' clause")
                     (Wrong (proof_not_of_type (pf_pos,proof) (prop_pos,prop),pf_pos))
  | HypLabel (h,a,spf,p) , c -> (encountered_while ("evaluating 'we know "^h^" because' clause"))
                                  ((check_prop psi a) >>                                 (*HypLabel*)
                                     ((check_pf psi gamma spf a) >>
                                        ((check_spf spf) >>
                                           (check_pf psi ((h,a)::gamma) p (prop_pos,c)))))
  | SpineApp (h,s)       , c -> (encountered_while "evaluating 'with' clause")           (*SpineApp*)
                                  ((lookup_hyps_result gamma h pf_pos) >>=
                                     (fun a ->
                                      (apply_spine psi gamma s a pf_pos) >>=
                                        (fun b -> alpha_equiv_prop_result b (prop_pos,c))))
  | Instantiate (h',a,(h,d),xs,p) , c -> (encountered_while ("evaluating 'we get "^h'^" instantiating "^h^"' clause"))
                                           ((lookup_hyps_result gamma (h,d) pf_pos) >>=  (*Instantiate*)
                                              (fun a' ->
                                               let new_prop = (instantiate_var xs a') in
                                               (alpha_equiv_prop_result a new_prop) >>
                                                 (check_pf psi ((h',new_prop)::gamma) p (prop_pos,c))))
  | Todo , c -> print_newline ();                                                        (*TODO*)
                printf "%s @." (incomplete_proof (prop_pos,c));
                printf "    @[%s @] @." (line_sprintf (fst pf_pos) (snd pf_pos));
                success := 1;
                return ()
