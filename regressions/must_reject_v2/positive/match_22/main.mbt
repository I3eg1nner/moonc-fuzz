enum E22 { A; B }
fn f(e : E22) -> Int { match e { A => 22 } }
fn main { println(f(A)) }
