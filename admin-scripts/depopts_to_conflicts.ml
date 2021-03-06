#!/usr/bin/env opam-admin.top

#directory "+../opam-lib";;
open Opam_admin_top;;

iter_packages ~opam:(fun _ opam ->
    let depopts =
      let formula = OpamFile.OPAM.depopts opam in
      let names =
        OpamStd.List.remove_duplicates @@
        List.map fst @@
        OpamFormula.atoms @@
        OpamFormula.formula_of_extended ~filter:(fun _ -> true) @@
        formula in
      OpamFormula.ors @@
      List.rev_map (fun n ->
          let flags =
            OpamStd.List.remove_duplicates @@
            OpamFormula.fold_left (fun acc (name,(flags,_)) ->
                if name = n then flags @ acc else acc)
              [] formula
          in
          OpamFormula.Atom (n, (flags,OpamFormula.Empty)))
        names
    in
    let conflicts = (* add complement of the depopts as conflicts *)
      let module NM = OpamPackage.Name.Map in
      let depopts = (* get back a map (name => version_constraint) *)
        (* XXX this takes _all_ the atoms not considering con/disjunctions *)
        OpamFormula.fold_left (fun acc (name,(_,f)) ->
            try
              NM.add name ((OpamFormula.ors [f; NM.find name acc])) acc
            with Not_found -> NM.add name f acc)
          NM.empty
          (OpamFile.OPAM.depopts opam) in
      let neg_depopts =
        NM.fold (fun name f acc ->
            if f = OpamFormula.Empty then acc else
            let f = OpamFormula.(neg (fun (op,v) -> neg_relop op, v) f) in
            match OpamFormula.to_cnf (OpamFormula.Atom (name,f)) with
            | [] -> acc
            | [conj] -> conj @ acc
            | [x;y] when x = y -> x @ acc
            | cnf ->
              (* Formula is not a conjunction, we are left with no choice
                 but to enumerate *)
              let f =
                OpamFormula.to_atom_formula @@ OpamFormula.ands @@
                List.map OpamFormula.of_disjunction cnf in
              let conflict_packages =
                OpamPackage.Set.filter
                  (fun pkg ->
                     OpamFormula.eval (fun atom -> OpamFormula.check atom pkg) f)
                  (OpamPackage.packages_of_name packages name)
              in
              OpamPackage.Set.fold (fun nv acc ->
                  (OpamPackage.name nv, Some (`Eq, OpamPackage.version nv))
                  :: acc)
                conflict_packages acc)
          depopts [] in
      let conflicts = OpamFile.OPAM.conflicts opam in
      let add_conflicts =
        let c = OpamFormula.to_disjunction conflicts in
        List.filter (fun f -> not (List.mem f c)) neg_depopts in
      OpamFormula.ands (conflicts :: [OpamFormula.of_disjunction add_conflicts])
    in
    let opam = OpamFile.OPAM.with_depopts opam depopts in
    let opam = OpamFile.OPAM.with_conflicts opam conflicts in
    opam)
  ()
;;
