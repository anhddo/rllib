module type S = sig
  (* Simulation Type *)
  type t = float list
  (* Should store all the information to uniquely identify any possible simulation state *)

  (* Can change based on what the simulation needs *)
  type action = float list

  type response = {
    observation : t;
    reward : float;
    terminated : bool;
    truncated : bool;
    info : string;
  }

  (* Creates a new simulation *)
  val create : unit -> t

  (* Resets the simulation and returns the first response again *)
  val reset : t -> t * string

  (* Applies the action to the environment, and returns the corresponding response *)
  val step : action -> response

  (* Take a simulation and render into a viewable format *)
  val render :
    t -> char list (* char list is temporary idea, can and may likely change *)
end
