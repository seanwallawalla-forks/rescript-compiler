  module Doc = Napkin_doc
  (* Napkin doesn't have parenthesized identifiers.
   * We don't support custom operators. *)
   let parenthesized_ident _name = true

   (* TODO: better allocation strategy for the buffer *)
   let escapeStringContents s =
     let len = String.length s in
     let b = Buffer.create len in
     for i = 0 to len - 1 do
       let c = (String.get [@doesNotRaise]) s i in
       if c = '\008'  then (
         Buffer.add_char b '\\';
         Buffer.add_char b 'b';
       ) else if c = '\009'  then (
         Buffer.add_char b '\\';
         Buffer.add_char b 't';
       ) else if c = '\010' then (
         Buffer.add_char b '\\';
         Buffer.add_char b 'n';
       ) else if c = '\013' then (
         Buffer.add_char b '\\';
         Buffer.add_char b 'r';
       ) else if c = '\034' then (
         Buffer.add_char b '\\';
         Buffer.add_char b '"';
       ) else if c = '\092' then (
         Buffer.add_char b '\\';
         Buffer.add_char b '\\';
       ) else (
         Buffer.add_char b c;
       );
     done;
     Buffer.contents b
 
   (* let rec print_ident fmt ident = match ident with
     | Outcometree.Oide_ident s -> Format.pp_print_string fmt s
     | Oide_dot (id, s) ->
       print_ident fmt id;
       Format.pp_print_char fmt '.';
       Format.pp_print_string fmt s
     | Oide_apply (id1, id2) ->
       print_ident fmt id1;
       Format.pp_print_char fmt '(';
       print_ident fmt id2;
       Format.pp_print_char fmt ')' *)
 
     let rec printOutIdentDoc (ident : Outcometree.out_ident) =
       match ident with
       | Oide_ident s -> Doc.text s
       | Oide_dot (ident, s) -> Doc.concat [
           printOutIdentDoc ident;
           Doc.dot;
           Doc.text s;
         ]
       | Oide_apply (call, arg) ->Doc.concat [
           printOutIdentDoc call;
           Doc.lparen;
           printOutIdentDoc arg;
           Doc.rparen;
         ]
 
   let printOutAttributeDoc (outAttribute: Outcometree.out_attribute) =
     Doc.concat [
       Doc.text "@";
       Doc.text outAttribute.oattr_name;
     ]
 
   let printOutAttributesDoc (attrs: Outcometree.out_attribute list) =
     match attrs with
     | [] -> Doc.nil
     | attrs ->
       Doc.concat [
         Doc.group (
           Doc.join ~sep:Doc.line (List.map printOutAttributeDoc attrs)
         );
         Doc.line;
       ]
 
   let rec collectArrowArgs (outType: Outcometree.out_type) args =
     match outType with
     | Otyp_arrow (label, argType, returnType) ->
       let arg = (label, argType) in
       collectArrowArgs returnType (arg::args)
     | _ as returnType ->
       (List.rev args, returnType)
 
   let rec collectFunctorArgs (outModuleType: Outcometree.out_module_type) args =
     match outModuleType with
     | Omty_functor (lbl, optModType, returnModType) ->
       let arg = (lbl, optModType) in
       collectFunctorArgs returnModType (arg::args)
     | _ ->
       (List.rev args, outModuleType)
 
   let rec printOutTypeDoc (outType: Outcometree.out_type) =
     match outType with
     | Otyp_abstract | Otyp_variant _ (* don't support poly-variants atm *) | Otyp_open -> Doc.nil
     | Otyp_alias (typ, aliasTxt) ->
       Doc.concat [
         printOutTypeDoc typ;
         Doc.text " as '";
         Doc.text aliasTxt
       ]
     | Otyp_constr (outIdent, []) ->
       printOutIdentDoc outIdent
     | Otyp_manifest (typ1, typ2) ->
         Doc.concat [
           printOutTypeDoc typ1;
           Doc.text " = ";
           printOutTypeDoc typ2;
         ]
     | Otyp_record record ->
       printRecordDeclarationDoc ~inline:true record
     | Otyp_stuff txt -> Doc.text txt
     | Otyp_var (ng, s) -> Doc.concat [
         Doc.text ("'" ^ (if ng then "_" else ""));
         Doc.text s
       ]
     | Otyp_object (fields, rest) -> printObjectFields fields rest
     | Otyp_class _ -> Doc.nil
     | Otyp_attribute (typ, attribute) ->
       Doc.group (
         Doc.concat [
           printOutAttributeDoc attribute;
           Doc.line;
           printOutTypeDoc typ;
         ]
       )
     (* example: Red | Blue | Green | CustomColour(float, float, float) *)
     | Otyp_sum constructors ->
       printOutConstructorsDoc constructors
 
     (* example: {"name": string, "age": int} *)
     | Otyp_constr (
         (Oide_dot ((Oide_ident "Js"), "t")),
         [Otyp_object (fields, rest)]
       ) -> printObjectFields fields rest
 
     (* example: node<root, 'value> *)
     | Otyp_constr (outIdent, args) ->
       let argsDoc = match args with
       | [] -> Doc.nil
       | args ->
         Doc.concat [
           Doc.lessThan;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutTypeDoc args
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.greaterThan;
         ]
       in
       Doc.group (
         Doc.concat [
           printOutIdentDoc outIdent;
           argsDoc;
         ]
       )
     | Otyp_tuple tupleArgs ->
       Doc.group (
         Doc.concat [
           Doc.lparen;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutTypeDoc tupleArgs
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rparen;
         ]
       )
     | Otyp_poly (vars, outType) ->
       Doc.group (
         Doc.concat [
           Doc.join ~sep:Doc.space (
             List.map (fun var -> Doc.text ("'" ^ var)) vars
           );
           printOutTypeDoc outType;
         ]
       )
     | Otyp_arrow _ as typ ->
       let (typArgs, typ) = collectArrowArgs typ [] in
       let args = Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
         List.map (fun (lbl, typ) ->
           if lbl = "" then
             printOutTypeDoc typ
           else
             Doc.group (
               Doc.concat [
                 Doc.text ("~" ^ lbl ^ ": ");
                 printOutTypeDoc typ
               ]
             )
         ) typArgs
       ) in
       let argsDoc =
         let needsParens = match typArgs with
         | [_, (Otyp_tuple _ | Otyp_arrow _)] -> true
         (* single argument should not be wrapped *)
         | ["", _] -> false
         | _ -> true
         in
         if needsParens then
           Doc.group (
             Doc.concat [
               Doc.lparen;
               Doc.indent (
                 Doc.concat [
                   Doc.softLine;
                   args;
                 ]
               );
               Doc.trailingComma;
               Doc.softLine;
               Doc.rparen;
             ]
           )
         else args
       in
       Doc.concat [
         argsDoc;
         Doc.text " => ";
         printOutTypeDoc typ;
       ]
     | Otyp_module (_modName, _stringList, _outTypes) ->
         Doc.nil
 
   and printObjectFields fields rest =
     let dots = match rest with
     | Some non_gen -> Doc.text ((if non_gen then "_" else "") ^ "..")
     | None -> Doc.nil
     in
     Doc.group (
       Doc.concat [
         Doc.lbrace;
         dots;
         Doc.indent (
           Doc.concat [
             Doc.softLine;
             Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
               List.map (fun (lbl, outType) -> Doc.group (
                 Doc.concat [
                   Doc.text ("\"" ^ lbl ^ "\": ");
                   printOutTypeDoc outType;
                 ]
               )) fields
             )
           ]
         );
         Doc.softLine;
         Doc.trailingComma;
         Doc.rbrace;
       ]
     )
 
 
   and printOutConstructorsDoc constructors =
     Doc.group (
       Doc.indent (
         Doc.concat [
           Doc.line;
           Doc.join ~sep:Doc.line (
             List.mapi (fun i constructor ->
               Doc.concat [
                 if i > 0 then Doc.text "| " else Doc.ifBreaks (Doc.text "| ") Doc.nil;
                 printOutConstructorDoc constructor;
               ]
             ) constructors
           )
         ]
       )
     )
 
   and printOutConstructorDoc (name, args, gadt) =
       let gadtDoc = match gadt with
       | Some outType ->
         Doc.concat [
           Doc.text ": ";
           printOutTypeDoc outType
         ]
       | None -> Doc.nil
       in
       let argsDoc = match args with
       | [] -> Doc.nil
       | [Otyp_record record] ->
         (* inline records
          *   | Root({
          *      mutable value: 'value,
          *      mutable updatedTime: float,
          *    })
          *)
         Doc.concat [
           Doc.lparen;
           Doc.indent (
             printRecordDeclarationDoc ~inline:true record;
           );
           Doc.rparen;
         ]
       | _types ->
         Doc.indent (
           Doc.concat [
             Doc.lparen;
             Doc.indent (
               Doc.concat [
                 Doc.softLine;
                 Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                   List.map printOutTypeDoc args
                 )
               ]
             );
             Doc.trailingComma;
             Doc.softLine;
             Doc.rparen;
           ]
         )
       in
       Doc.group (
         Doc.concat [
           Doc.text name;
           argsDoc;
           gadtDoc
         ]
       )
 
   and printRecordDeclRowDoc (name, mut, arg) =
     Doc.group (
       Doc.concat [
         if mut then Doc.text "mutable " else Doc.nil;
         Doc.text name;
         Doc.text ": ";
         printOutTypeDoc arg;
       ]
     )
 
   and printRecordDeclarationDoc ~inline rows =
     let content = Doc.concat [
       Doc.lbrace;
       Doc.indent (
         Doc.concat [
           Doc.softLine;
           Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
             List.map printRecordDeclRowDoc rows
           )
         ]
       );
       Doc.trailingComma;
       Doc.softLine;
       Doc.rbrace;
     ] in
     if not inline then
       Doc.group content
     else content
 
   let printOutType fmt outType =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutTypeDoc outType))
 
   let printTypeParameterDoc (typ, (co, cn)) =
     Doc.concat [
       if not cn then Doc.text "+" else if not co then Doc.text "-" else Doc.nil;
       if typ = "_" then Doc.text "_" else Doc.text ("'" ^ typ)
     ]
 
 
   let rec printOutSigItemDoc (outSigItem : Outcometree.out_sig_item) =
     match outSigItem with
     | Osig_class _ | Osig_class_type _ -> Doc.nil
     | Osig_ellipsis -> Doc.dotdotdot
     | Osig_value valueDecl ->
       Doc.group (
         Doc.concat [
           printOutAttributesDoc valueDecl.oval_attributes;
           Doc.text (
             match valueDecl.oval_prims with | [] -> "let " | _ -> "external "
           );
           Doc.text valueDecl.oval_name;
           Doc.text ":";
           Doc.space;
           printOutTypeDoc valueDecl.oval_type;
           match valueDecl.oval_prims with
           | [] -> Doc.nil
           | primitives -> Doc.indent (
               Doc.concat [
                 Doc.text " =";
                 Doc.line;
                 Doc.group (
                   Doc.join ~sep:Doc.line (List.map (fun prim -> Doc.text ("\"" ^ prim ^ "\"")) primitives)
                 )
               ]
             )
         ]
       )
   | Osig_typext (outExtensionConstructor, _outExtStatus) ->
     printOutExtensionConstructorDoc outExtensionConstructor
   | Osig_modtype (modName, Omty_signature []) ->
     Doc.concat [
       Doc.text "module type ";
       Doc.text modName;
     ]
   | Osig_modtype (modName, outModuleType) ->
     Doc.group (
       Doc.concat [
         Doc.text "module type ";
         Doc.text modName;
         Doc.text " = ";
         printOutModuleTypeDoc outModuleType;
       ]
     )
   | Osig_module (modName, Omty_alias ident, _) ->
     Doc.group (
       Doc.concat [
         Doc.text "module ";
         Doc.text modName;
         Doc.text " =";
         Doc.line;
         printOutIdentDoc ident;
       ]
     )
   | Osig_module (modName, outModType, outRecStatus) ->
      Doc.group (
       Doc.concat [
         Doc.text (
           match outRecStatus with
           | Orec_not -> "module "
           | Orec_first -> "module rec "
           | Orec_next -> "and"
         );
         Doc.text modName;
         Doc.text " = ";
         printOutModuleTypeDoc outModType;
       ]
     )
   | Osig_type (outTypeDecl, outRecStatus) ->
     (* TODO: manifest ? *)
     let attrs = match outTypeDecl.otype_immediate, outTypeDecl.otype_unboxed with
     | false, false -> Doc.nil
     | true, false ->
       Doc.concat [Doc.text "@immediate"; Doc.line]
     | false, true ->
       Doc.concat [Doc.text "@unboxed"; Doc.line]
     | true, true ->
       Doc.concat [Doc.text "@immediate @unboxed"; Doc.line]
     in
     let kw = Doc.text (
       match outRecStatus with
       | Orec_not -> "type "
       | Orec_first -> "type rec "
       | Orec_next -> "and "
     ) in
     let typeParams = match outTypeDecl.otype_params with
     | [] -> Doc.nil
     | _params -> Doc.group (
         Doc.concat [
           Doc.lessThan;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printTypeParameterDoc outTypeDecl.otype_params
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.greaterThan;
         ]
       )
     in
     let privateDoc = match outTypeDecl.otype_private with
     | Asttypes.Private -> Doc.text "private "
     | Public -> Doc.nil
     in
     let kind = match outTypeDecl.otype_type with
     | Otyp_open -> Doc.concat [
         Doc.text " = ";
         privateDoc;
         Doc.text "..";
       ]
     | Otyp_abstract -> Doc.nil
     | Otyp_record record -> Doc.concat [
         Doc.text " = ";
         privateDoc;
         printRecordDeclarationDoc ~inline:false record;
       ]
     | typ -> Doc.concat [
         Doc.text " = ";
         printOutTypeDoc typ
       ]
     in
     let constraints =  match outTypeDecl.otype_cstrs with
     | [] -> Doc.nil
     | _ -> Doc.group (
       Doc.concat [
         Doc.line;
         Doc.indent (
           Doc.concat [
             Doc.hardLine;
             Doc.join ~sep:Doc.line (List.map (fun (typ1, typ2) ->
               Doc.group (
                 Doc.concat [
                   Doc.text "constraint ";
                   printOutTypeDoc typ1;
                   Doc.text " =";
                   Doc.indent (
                     Doc.concat [
                       Doc.line;
                       printOutTypeDoc typ2;
                     ]
                   )
                 ]
               )
             ) outTypeDecl.otype_cstrs)
           ]
         )
       ]
     ) in
     Doc.group (
       Doc.concat [
         attrs;
         Doc.group (
           Doc.concat [
             attrs;
             kw;
             Doc.text outTypeDecl.otype_name;
             typeParams;
             kind
           ]
         );
         constraints
       ]
     )
 
   and printOutModuleTypeDoc (outModType : Outcometree.out_module_type) =
     match outModType with
     | Omty_abstract -> Doc.nil
     | Omty_ident ident -> printOutIdentDoc ident
     (* example: module Increment = (M: X_int) => X_int *)
     | Omty_functor _ ->
       let (args, returnModType) = collectFunctorArgs outModType [] in
       let argsDoc = match args with
       | [_, None] -> Doc.text "()"
       | args ->
         Doc.group (
           Doc.concat [
             Doc.lparen;
             Doc.indent (
               Doc.concat [
                 Doc.softLine;
                 Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                   List.map (fun (lbl, optModType) -> Doc.group (
                     Doc.concat [
                       Doc.text lbl;
                       match optModType with
                       | None -> Doc.nil
                       | Some modType -> Doc.concat [
                           Doc.text ": ";
                           printOutModuleTypeDoc modType;
                         ]
                     ]
                   )) args
                 )
               ]
             );
             Doc.trailingComma;
             Doc.softLine;
             Doc.rparen;
           ]
         )
       in
       Doc.group (
         Doc.concat [
           argsDoc;
           Doc.text " => ";
           printOutModuleTypeDoc returnModType
         ]
       )
     | Omty_signature [] -> Doc.nil
     | Omty_signature signature ->
       Doc.breakableGroup ~forceBreak:true (
         Doc.concat [
           Doc.lbrace;
           Doc.indent (
             Doc.concat [
               Doc.line;
               printOutSignatureDoc signature;
             ]
           );
           Doc.softLine;
           Doc.rbrace;
         ]
       )
     | Omty_alias _ident -> Doc.nil
 
   and printOutSignatureDoc (signature : Outcometree.out_sig_item list) =
     let rec loop signature acc =
       match signature with
       | [] -> List.rev acc
       | Outcometree.Osig_typext(ext, Oext_first) :: items ->
         (* Gather together the extension constructors *)
         let rec gather_extensions acc items =
           match items with
               Outcometree.Osig_typext(ext, Oext_next) :: items ->
                 gather_extensions
                   ((ext.oext_name, ext.oext_args, ext.oext_ret_type) :: acc)
                   items
             | _ -> (List.rev acc, items)
         in
         let exts, items =
           gather_extensions
             [(ext.oext_name, ext.oext_args, ext.oext_ret_type)]
             items
         in
         let te =
           { Outcometree.otyext_name = ext.oext_type_name;
             otyext_params = ext.oext_type_params;
             otyext_constructors = exts;
             otyext_private = ext.oext_private }
         in
         let doc = printOutTypeExtensionDoc te in
         loop items (doc::acc)
       | item::items ->
         let doc = printOutSigItemDoc item in
         loop items (doc::acc)
     in
     match loop signature [] with
     | [doc] -> doc
     | docs ->
       Doc.breakableGroup ~forceBreak:true (
         Doc.join ~sep:Doc.line docs
       )
 
   and printOutExtensionConstructorDoc (outExt : Outcometree.out_extension_constructor) =
     let typeParams = match outExt.oext_type_params with
     | [] -> Doc.nil
     | params ->
       Doc.group(
         Doc.concat [
           Doc.lessThan;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (List.map
                 (fun ty -> Doc.text (if ty = "_" then ty else "'" ^ ty))
                 params
 
               )
             ]
           );
           Doc.softLine;
           Doc.greaterThan;
         ]
       )
 
     in
     Doc.group (
       Doc.concat [
         Doc.text "type ";
         Doc.text outExt.oext_type_name;
         typeParams;
         Doc.text " +=";
         Doc.line;
         if outExt.oext_private = Asttypes.Private then
           Doc.text "private "
         else
           Doc.nil;
         printOutConstructorDoc
           (outExt.oext_name, outExt.oext_args, outExt.oext_ret_type)
       ]
     )
 
   and printOutTypeExtensionDoc (typeExtension : Outcometree.out_type_extension) =
     let typeParams = match typeExtension.otyext_params with
     | [] -> Doc.nil
     | params ->
       Doc.group(
         Doc.concat [
           Doc.lessThan;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (List.map
                 (fun ty -> Doc.text (if ty = "_" then ty else "'" ^ ty))
                 params
 
               )
             ]
           );
           Doc.softLine;
           Doc.greaterThan;
         ]
       )
 
     in
     Doc.group (
       Doc.concat [
         Doc.text "type ";
         Doc.text typeExtension.otyext_name;
         typeParams;
         Doc.text " +=";
         if typeExtension.otyext_private = Asttypes.Private then
           Doc.text "private "
         else
           Doc.nil;
         printOutConstructorsDoc typeExtension.otyext_constructors;
       ]
     )
 
   let printOutSigItem fmt outSigItem =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutSigItemDoc outSigItem))
 
   let printOutSignature fmt signature =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutSignatureDoc signature))
 
   let validFloatLexeme s =
     let l = String.length s in
     let rec loop i =
       if i >= l then s ^ "." else
       match (s.[i] [@doesNotRaise]) with
       | '0' .. '9' | '-' -> loop (i+1)
       | _ -> s
     in loop 0
 
   let floatRepres f =
     match classify_float f with
     | FP_nan -> "nan"
     | FP_infinite ->
       if f < 0.0 then "neg_infinity" else "infinity"
     | _ ->
       let float_val =
         let s1 = Printf.sprintf "%.12g" f in
         if f = (float_of_string [@doesNotRaise]) s1 then s1 else
         let s2 = Printf.sprintf "%.15g" f in
         if f = (float_of_string [@doesNotRaise]) s2 then s2 else
         Printf.sprintf "%.18g" f
       in validFloatLexeme float_val
 
   let rec printOutValueDoc (outValue : Outcometree.out_value) =
     match outValue with
     | Oval_array outValues ->
       Doc.group (
         Doc.concat [
           Doc.lbracket;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutValueDoc outValues
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rbracket;
         ]
       )
     | Oval_char c -> Doc.text ("'" ^ (Char.escaped c) ^ "'")
     | Oval_constr (outIdent, outValues) ->
       Doc.group (
         Doc.concat [
           printOutIdentDoc outIdent;
           Doc.lparen;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutValueDoc outValues
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rparen;
         ]
       )
     | Oval_ellipsis -> Doc.text "..."
     | Oval_int i -> Doc.text (Format.sprintf "%i" i)
     | Oval_int32 i -> Doc.text (Format.sprintf "%lil" i)
     | Oval_int64 i -> Doc.text (Format.sprintf "%LiL" i)
     | Oval_nativeint i -> Doc.text (Format.sprintf "%nin" i)
     | Oval_float f -> Doc.text (floatRepres f)
     | Oval_list outValues ->
       Doc.group (
         Doc.concat [
           Doc.text "list[";
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutValueDoc outValues
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rbracket;
         ]
       )
     | Oval_printer fn ->
       let fmt = Format.str_formatter in
       fn fmt;
       let str = Format.flush_str_formatter () in
       Doc.text str
     | Oval_record rows ->
       Doc.group (
         Doc.concat [
           Doc.lparen;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map (fun (outIdent, outValue) -> Doc.group (
                     Doc.concat [
                       printOutIdentDoc outIdent;
                       Doc.text ": ";
                       printOutValueDoc outValue;
                     ]
                   )
                 ) rows
               );
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rparen;
         ]
       )
     | Oval_string (txt, _sizeToPrint, _kind) ->
       Doc.text (escapeStringContents txt)
     | Oval_stuff txt -> Doc.text txt
     | Oval_tuple outValues ->
       Doc.group (
         Doc.concat [
           Doc.lparen;
           Doc.indent (
             Doc.concat [
               Doc.softLine;
               Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                 List.map printOutValueDoc outValues
               )
             ]
           );
           Doc.trailingComma;
           Doc.softLine;
           Doc.rparen;
         ]
       )
     (* Not supported by NapkinScript *)
     | Oval_variant _ -> Doc.nil
 
   let printOutExceptionDoc exc outValue =
     match exc with
     | Sys.Break -> Doc.text "Interrupted."
     | Out_of_memory -> Doc.text "Out of memory during evaluation."
     | Stack_overflow ->
       Doc.text "Stack overflow during evaluation (looping recursion?)."
     | _ ->
       Doc.group (
         Doc.indent(
           Doc.concat [
             Doc.text "Exception:";
             Doc.line;
             printOutValueDoc outValue;
           ]
         )
       )
 
   let printOutPhraseSignature signature =
     let rec loop signature acc =
      match signature with
      | [] -> List.rev acc
      | (Outcometree.Osig_typext(ext, Oext_first), None)::signature ->
         (* Gather together extension constructors *)
         let rec gather_extensions acc items =
           match items with
           |  (Outcometree.Osig_typext(ext, Oext_next), None)::items ->
               gather_extensions
                 ((ext.oext_name, ext.oext_args, ext.oext_ret_type)::acc)
                 items
           | _ -> (List.rev acc, items)
         in
         let exts, signature =
           gather_extensions
             [(ext.oext_name, ext.oext_args, ext.oext_ret_type)]
             signature
         in
         let te =
           { Outcometree.otyext_name = ext.oext_type_name;
             otyext_params = ext.oext_type_params;
             otyext_constructors = exts;
             otyext_private = ext.oext_private }
         in
         let doc = printOutTypeExtensionDoc te in
         loop signature (doc::acc)
      | (sigItem, optOutValue)::signature ->
        let doc = match optOutValue with
         | None ->
           printOutSigItemDoc sigItem
         | Some outValue ->
           Doc.group (
             Doc.concat [
               printOutSigItemDoc sigItem;
               Doc.text " = ";
               printOutValueDoc outValue;
             ]
           )
        in
        loop signature (doc::acc)
      in
      Doc.breakableGroup ~forceBreak:true (
        Doc.join ~sep:Doc.line (loop signature [])
      )
 
   let printOutPhraseDoc (outPhrase : Outcometree.out_phrase) =
     match outPhrase with
     | Ophr_eval (outValue, outType) ->
       Doc.group (
         Doc.concat [
           Doc.text "- : ";
           printOutTypeDoc outType;
           Doc.text " =";
           Doc.indent (
             Doc.concat [
               Doc.line;
               printOutValueDoc outValue;
             ]
           )
         ]
       )
     | Ophr_signature [] -> Doc.nil
     | Ophr_signature signature -> printOutPhraseSignature signature
     | Ophr_exception (exc, outValue) ->
       printOutExceptionDoc exc outValue
 
   let printOutPhrase fmt outPhrase =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutPhraseDoc outPhrase))
 
   let printOutModuleType fmt outModuleType =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutModuleTypeDoc outModuleType))
 
   let printOutTypeExtension fmt typeExtension =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutTypeExtensionDoc typeExtension))
 
   let printOutValue fmt outValue =
     Format.pp_print_string fmt
       (Doc.toString ~width:80 (printOutValueDoc outValue))
 
   

 
   
(* Not supported in Napkin *)
(* Oprint.out_class_type *)
   let setup  = lazy begin
    Oprint.out_value := printOutValue;
    Oprint.out_type := printOutType;
    Oprint.out_module_type := printOutModuleType;
    Oprint.out_sig_item := printOutSigItem;
    Oprint.out_signature := printOutSignature;
    Oprint.out_type_extension := printOutTypeExtension;
    Oprint.out_phrase := printOutPhrase
  end  
     