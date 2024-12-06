(* Variables to store the parsed values *)
let episode = ref 0
let model_path = ref ""

let render = ref false

(* Function to set the episode *)

(* Command-line argument specification *)
let speclist = [
  ("--episode", Arg.Set_int episode, "Set the number of episodes (integer)");
  ("--model-path", Arg.Set_string model_path, "Set the path to the model (string)");
  ("--render", Arg.Set render, "Enable rendering (boolean flag, default: false)");
]

(* Main program *)
let run (episode: int) (model_path: string) (render: bool) = 

  let module Algo_config = struct
    let model_path = model_path
  end in

  let module Pendulum_env = Pendulum.Make (struct
    let render = false
  end) in

  let module Pendulum_env_render = Pendulum.Make (struct
    let render = true
  end) in

  let module Vpg_algo = Vpg.Make (Algo_config) (Pendulum_env) in

  let module Vpg_algo_render =
    Vpg.Make (Algo_config) (Pendulum_env_render) in
  if render then
    Vpg_algo_render.train episode
  else
  (Vpg_algo.train episode;
  Vpg_algo.save_model ();)

  

(* Entry point *)
let () = 
  Arg.parse speclist print_endline "";

  (* Validate required arguments *)
  run !episode !model_path !render;
