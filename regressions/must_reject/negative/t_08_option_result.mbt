fn compute() -> String {
  let o : Int? = Some(3)
  let n : Int? = None
  let r : Result[Int, String] = Ok(5)
  let e : Result[Int, String] = Err("bad")
  let os = match o { Some(x) => x.to_string(); None => "none" }
  let ns = match n { Some(x) => x.to_string(); None => "none" }
  let rs = match r { Ok(x) => x.to_string(); Err(m) => m }
  let es = match e { Ok(x) => x.to_string(); Err(m) => m }
  "\{os}|\{ns}|\{rs}|\{es}"
}
fn main { println(compute()) }
