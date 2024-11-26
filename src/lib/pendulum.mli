(* Pendulum is a Simulation *)

(* type t = float list (* [angle; angular_speed] *)
type action = float list (* [applied_torque] *)

type response = {
  observation : t;
  reward : float;
  terminated : bool;
  truncated : bool;
  info : string;
  internal_state : t;
}
val reset : unit -> t
val render : t -> unit
val create : unit -> t *)
include Simulation.T

val normalize_angle : float -> float
val modulo : float -> float -> float
val square : float -> float
val random_between : float -> float -> float
val clip : 'a -> 'a -> 'a -> 'a
val simulate : t -> unit
