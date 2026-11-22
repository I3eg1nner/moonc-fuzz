enum E19 { A; B }
fn f(e : E19) -> Int { match e { A => 19 } }
fn main { println(f(A)) }
