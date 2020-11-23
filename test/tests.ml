let show_raise f =
  try
    ignore (f () : int)
  with exn ->
    let s =
      match exn with
      | Unix.Unix_error _ ->
        (* For compat with Windows *)
        "Unix.Unix_error _"
      | exn -> Printexc.to_string exn
    in
    Printf.printf "raised %s" s

let%expect_test "non-existing program" =
  show_raise (fun () ->
    Spawn.spawn () ~prog:"/doesnt-exist" ~argv:["blah"]);
  [%expect {|
    raised Unix.Unix_error _
  |}]

let%expect_test "non-existing dir" =
  show_raise (fun () ->
    Spawn.spawn () ~prog:"/bin/true" ~argv:["true"]
      ~cwd:(Path "/doesnt-exist"));
  [%expect {|
    raised Unix.Unix_error _
  |}]

let wait pid =
  match snd (Unix.waitpid [] pid) with
  | WEXITED   0 -> ()
  | WEXITED   n -> Printf.ksprintf failwith "exited with code %d" n
  | WSIGNALED n -> Printf.ksprintf failwith "got signal %d" n
  | WSTOPPED  _ -> assert false

let%expect_test "cwd:Fd" =
  if Sys.win32 then
    print_string "/tmp"
  else begin
    let fd = Unix.openfile "/tmp" [O_RDONLY] 0 in
    wait (Spawn.spawn () ~prog:"/bin/pwd" ~argv:["pwd"] ~cwd:(Fd fd));
    Unix.close fd
  end;
  [%expect {|
    /tmp
  |}]

let%expect_test "cwd:Fd (invalid)" =
  show_raise (fun () ->
    if Sys.win32 then
      raise (Unix.Unix_error(ENOTDIR, "fchdir", ""))
    else
      Spawn.spawn () ~prog:"/bin/pwd" ~argv:["pwd"] ~cwd:(Fd Unix.stdin));
  [%expect {|
    raised Unix.Unix_error _
  |}]


module Program_lookup = struct
  let path_sep = if Sys.win32 then ';'    else ':'
  let exe_ext  = if Sys.win32 then ".exe" else ""

  let split_path s =
    let rec loop i j =
      if j = String.length s then
        [String.sub s i (j - i)]
      else if s.[j] = path_sep then
        String.sub s i (j - i) :: loop (j + 1) (j + 1)
      else
        loop i (j + 1)
    in
    loop 0 0

  let path =
    match Sys.getenv "PATH" with
    | exception Not_found -> []
    | s -> split_path s

  let find_prog prog =
    let rec search = function
      | [] -> Printf.ksprintf failwith "Program %S not found in PATH!" prog
      | dir :: rest ->
        let fn = Filename.concat dir prog ^ exe_ext in
        if Sys.file_exists fn then
          fn
        else
          search rest
    in
    search path
end

let%expect_test "inheriting stdout with close-on-exec set" =
  (* CR-soon jdimino for jdimino: the test itself seems to pass,
     however there seem to be another issue related to ppx_expect and
     Windows. *)
  if Sys.win32 then
    print_string "hello world"
  else begin
    Unix.set_close_on_exec Unix.stdout;
    let shell, arg =
      if Sys.win32 then
        "cmd", "/c"
      else
        "sh", "-c"
    in
    let prog = Program_lookup.find_prog shell in
    wait (Spawn.spawn () ~prog ~argv:[shell; arg; {|echo "hello world"|}]);
  end;
  [%expect {| hello world |}]

let%expect_test "prog relative to cwd" =
  if Sys.win32 then
    print_string "Hello, world!"
  else
    wait (Spawn.spawn () ~prog:"./hello.exe" ~argv:["hello"] ~cwd:(Path "exe"));
  [%expect {| Hello, world! |}]

let%expect_test "env" =
  let tst v =
    let env = match v with
      | None -> Spawn.Env.of_list []
      | Some v -> Spawn.Env.of_list ["FOO=" ^ v]
    in
    wait (Spawn.spawn () ~env ~prog:"./print_env.exe" ~argv:["print_env"] ~cwd:(Path "exe"))
  in
  tst (Some "foo");
  [%expect {| Some "foo" |}];
  tst None;
  [%expect {| None |}];
  tst (Some "");
  [%expect {| Some "" |}]
