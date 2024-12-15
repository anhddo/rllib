open Torch
open Base_algorithm

module Make (Algo_config : Algo_config) (Env : Simulation.S) = struct
  include Algo_config
  module State_action_env = State_action.Make (Env)

  (* let state_bin = State_action_env.q_config.state_bin *)
  let action_bin = State_action_env.q_config.action_bin
  let obs_dim = State_action_env.q_config.obs_dim

  (*Get action dimension*)
  let action_dim =
    match action_bin with Discrete n -> n | Continuous x -> x.num_bins

  (*load model*)
  (* let load_vpg_params (filename : string) =
     () *)

  let build_model input_size output_size hidden_size =
    let vs = Var_store.create ~name:"nn" () in
    let fc1 = Layer.linear vs ~input_dim:input_size hidden_size in
    let fc2 = Layer.linear vs ~input_dim:hidden_size output_size in
    object
      method forward input =
        input |> Layer.forward fc1 |> Tensor.relu |> Layer.forward fc2

      method var_store = vs
    end
  (* let input_size = obs_dim
     let output_size = action_dim
     let hidden_size = 3 *)
  (* let model = build_model input_size output_size hidden_size *)

  let load_vars vs filename =
    let tensors_fn = Serialize.load_multi ~filename in
    let names = Var_store.all_vars vs |> List.map fst in
    let tensors = tensors_fn ~names in
    Tensor.no_grad (fun () ->
        List.iter2
          (fun name tensor ->
            match List.assoc_opt name (Var_store.all_vars vs) with
            | Some existing_tensor -> Tensor.copy_ ~src:tensor existing_tensor
            | None ->
                Printf.eprintf "Warning: Tensor %s not found in Var_store\n"
                  name)
          names tensors);
    List.iter
      (fun (_, tensor) -> ignore (Tensor.set_requires_grad ~r:true tensor))
      (Var_store.all_vars vs);
    Printf.printf "All variables loaded from %s\n" filename

  let initialize_or_load_model () =
    let input_size = obs_dim in
    let output_size = action_dim in
    let hidden_size = 3 in
    let model_path = model_path in
    let model = build_model input_size output_size hidden_size in
    if Sys.file_exists model_path then (
      Printf.printf "Model file found at %s. Loading model...\n" model_path;
      load_vars model#var_store model_path)
    else
      Printf.printf "No model file found at %s. Initializing new model...\n"
        model_path;
    model

  let model = initialize_or_load_model ()

  let save_vars vs filename =
    let vars = Var_store.all_vars vs in
    Serialize.save_multi ~named_tensors:vars ~filename;
    Printf.printf "All variables saved to %s\n" filename

  (*save model using Sexp*)
  let save_model () =
    let vs = model#var_store in
    save_vars vs model_path;
    Printf.printf "Model saved to path: %s\n" model_path

  (* Select an action using softmax probability sampling *)
  let select_action model obs =
    let obs_tensor = Tensor.of_float1 obs |> Tensor.unsqueeze ~dim:0 in
    let probs =
      model#forward obs_tensor
      |> Tensor.softmax ~dim:(-1) ~dtype:(Torch_core.Kind.T Float)
    in

    (* let probs_ = Tensor.squeeze probs in
       print_tensor_info probs_; *)

    (* Sample an action based on the probabilities *)
    let action_tensor =
      Tensor.multinomial probs ~num_samples:1 ~replacement:true
    in
    let action =
      Tensor.select action_tensor ~dim:0 ~index:0 |> Tensor.int_value
    in
    (* Get the probability of the selected action *)
    let action_prob = Tensor.select probs ~dim:1 ~index:action in
    (action, action_prob)

  (* Updates the vpg parameters using the discounted cumulative reward *)
  let update_policy rewards probs optimizer =
    let log_probs = Tensor.log probs in
    (* print_tensor_info rewards;
       print_tensor_info log_probs; *)
    let loss = Tensor.neg (Tensor.sum (Tensor.mul log_probs rewards)) in
    Optimizer.zero_grad optimizer;
    Tensor.backward loss ~keep_graph:true;
    Optimizer.step optimizer;
    Printf.printf "Loss: %f\n%!" (Tensor.float_value loss)

  (* Calculate the discounted cumulative reward *)
  let calculate_returns (rewards : float list) (gamma : float) : float list =
    (* chronological order input and output*)
    let rec aux (acc : float) (returns : float list) = function
      | [] -> returns
      | r :: rs ->
          let g_t = r +. (gamma *. acc) in
          aux g_t (g_t :: returns) rs
    in
    aux 0.0 [] (List.rev rewards)

  (* Standardize trajectories and discounted cumulative reward *)
  let update_trajectories (rewards : float list) (gamma : float) =
    let returns = calculate_returns (List.rev rewards) gamma in

    (* let print_rewards rewards =
         List.iter (fun r -> Printf.printf "%f " r) rewards;
         print_endline ""
       in
       print_rewards rewards;
       Printf.printf "\n";
       print_rewards returns;
       let length = List.length returns in
       Printf.printf "Length of returns: %d\n" length; *)
    let mean =
      List.fold_left ( +. ) 0.0 returns /. float_of_int (List.length returns)
    in
    let variance =
      List.fold_left (fun acc x -> acc +. ((x -. mean) ** 2.0)) 0.0 returns
      /. float_of_int (List.length returns)
    in
    let std_dev = sqrt (variance +. 1e-8) in
    let standardized_returns =
      List.map (fun r -> (r -. mean) /. std_dev) returns
    in
    let standardized_returns_tensor =
      Tensor.of_float1 (Array.of_list standardized_returns)
    in
    standardized_returns_tensor

  (* let print_tensor_info tensor =
     let shape = Tensor.shape tensor in
     let shape_str = String.concat ", " (List.map string_of_int shape) in
     Printf.printf "Probs shape: [%s]\n%!" shape_str;
     Printf.printf "Probs content: %s\n%!" (Tensor.to_string tensor ~line_size:80) *)

  (* let print_tensor_version tensor name =
     Printf.printf "Tensor: %s, Version: %d\n" name (Int64.to_int (Tensor._version tensor)) *)

  (*train model*)
  let train () =
    let learning_rate = 0.01 in
    let max_steps = 250 in
    let gamma = 0.7 in
    let optimizer = Optimizer.adam model#var_store ~learning_rate in
    for _episode = 1 to episode do
      let state, internal_state = Env.reset () in
      let state = Array.of_list state in
      let rec run_step t state rewards probs internal_state =
        (* Printf.printf "Time step T: %d\n" t; *)
        if t >= max_steps then
          (* Printf.printf "Episode %d Success: Time Steps: %d\n%!" episode t *)
          ()
        else
          let action, prob = select_action model state in
          (* Printf.printf "Selected action: %d\n%!" action; *)
          (* print_tensor_version probs "Probs before concatenation";
             print_tensor_version prob "Prob to concatenate"; *)
          let probs =
            if Tensor.shape probs = [ 0 ] then prob
            else
              (* Tensor.cat [probs; prob] ~dim:0 *)
              (* prob *)
              (* Printf.printf "here\n"; *)
              Tensor.cat [ probs; prob ] ~dim:0
          in

          (* print_tensor_version probs "Probs after concatenation"; *)
          (* Printf.printf "Probs requires grad: %b\n" (Tensor.requires_grad probs); *)
          (* print_endline "state : ";
             Array.iter (fun x -> Printf.printf "%f " x) state;
             Printf.printf "\n";
             print_endline "probs accumulated: ";
             print_tensor_info probs; *)
          let passing_action_to_env =
            match action_bin with
            | Discrete _ -> [ float_of_int action ]
            | Continuous x -> [ State_action_env.bin_to_value action x ]
          in

          (* Printf.printf "Action passed to environment: ";
             List.iter (fun f -> Printf.printf "%f " f) passing_action_to_env;
             Printf.printf "\n"; *)
          let response = Env.step internal_state passing_action_to_env in
          let next_state = response.observation in
          let reward = response.reward in
          let is_done = response.terminated in
          let truncated = response.truncated in
          let next_state = Array.of_list next_state in
          let rewards = reward :: rewards in
          if is_done || truncated then (
            (* if true then *)
            let rewards_tensor = update_trajectories rewards gamma in
            (* print_weights model#var_store; *)
            (* print_gradients model#var_store; *)
            update_policy rewards_tensor probs optimizer;
            let total_reward = List.fold_left ( +. ) 0.0 rewards in
            Printf.printf "Episode %d: Total Reward: %f\n%!" _episode
              total_reward)
          else (
            Env.render response.internal_state;
            run_step (t + 1) next_state rewards probs response.internal_state)
      in
      let probs = Tensor.zeros [ 0 ] in
      run_step 0 state [] probs internal_state
    done
end