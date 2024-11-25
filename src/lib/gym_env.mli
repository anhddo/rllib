(* A Testing Enviroment from Python's Gymnasium*)

module Make : functor (_ : Simulation.Config) -> sig
  include Simulation.T

  val reset : unit -> t
  val step : t -> action -> response
  val render : t -> char list
end

module Make_config (_ : Simulation.Config) : sig
  type continuous_bin = { low : float; high : float; num_bins : int }

  type bin = Discrete of int | Continuous of continuous_bin

  type q_table_config = {
    obs_dim : int;
    action_dim : int;
    state_bin : int;
    action_bin : bin;
    is_continuous_action : bool;
  }
  val q_config: q_table_config
  val value_to_bin : float -> float -> float -> int -> int
  val convert_state_to_bin : float list -> int
  val bin_to_value : int -> continuous_bin -> float
end
