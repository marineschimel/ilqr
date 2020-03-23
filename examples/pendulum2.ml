open Owl
module AD = Algodiff.D

let () = Printexc.record_backtrace true
let dir = Cmdargs.(get_string "-d" |> force ~usage:"-d [dir]")
let in_dir = Printf.sprintf "%s/%s" dir

module P = struct
  let n = 2
  let m = 1
  let n_steps = 2000
  let dt = AD.F 1E-3
  let g = AD.F 9.8
  let mu = AD.F 0.01

  let dyn ~u ~x =
    let x1 = AD.Maths.get_slice [ []; [ 0 ] ] x in
    let x2 = AD.Maths.get_slice [ []; [ 1 ] ] x in
    let sx1 = AD.Maths.sin x1 in
    let dx2 = AD.Maths.((g * sx1) - (mu * x2) + u) in
    let dx = [| x2; dx2 |] |> AD.Maths.concatenate ~axis:1 in
    AD.Maths.(x + (dx * dt))


  let running_loss =
    let r = Owl.Mat.(eye m *$ 1E-5) |> AD.pack_arr in
    fun ~x:_x ~u -> AD.(Maths.(F 0.5 * sum' (u *@ r * u)))


  let final_loss =
    let q = Owl.Mat.(eye n *$ 5.) |> AD.pack_arr in
    let xstar = [| [| 0.; 0. |] |] |> Mat.of_arrays |> AD.pack_arr in
    fun ~x ->
      let dx = AD.Maths.(xstar - x) in
      AD.(Maths.(F 0.5 * sum' (dx *@ q * dx)))
end

module M = Ilqr.Default.Make (P)

let () =
  let x0 = [| [| Const.pi; 0. |] |] |> Mat.of_arrays |> AD.pack_arr in
  let us = List.init P.n_steps (fun _ -> AD.Mat.zeros 1 P.m) in
  M.trajectory x0 us |> AD.unpack_arr |> Mat.save_txt ~out:(in_dir "traj0");
  let stop =
    let cprev = ref 1E9 in
    fun k us ->
      let c = M.loss x0 us in
      let pct_change = abs_float (c -. !cprev) /. !cprev in
      if k mod 1 = 0
      then (
        Printf.printf "iter %i | cost %f | pct change %f\n%!" k c pct_change;
        cprev := c;
        M.trajectory x0 us |> AD.unpack_arr |> Mat.save_txt ~out:(in_dir "traj1");
        us
        |> Array.of_list
        |> AD.Maths.concatenate ~axis:0
        |> AD.unpack_arr
        |> Mat.save_txt ~out:(in_dir "us"));
      pct_change < 1E-3
  in
  M.learn ~stop x0 us |> ignore