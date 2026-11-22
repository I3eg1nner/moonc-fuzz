enum E27 { A; B }
fn f(e : E27) -> Int { match e { A => 27 } }
fn main { println(f(A)) }
