enum E8 { A; B }
fn f(e : E8) -> Int { match e { A => 8 } }
fn main { println(f(A)) }
