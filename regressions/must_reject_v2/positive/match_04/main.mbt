enum E4 { A; B }
fn f(e : E4) -> Int { match e { A => 4 } }
fn main { println(f(A)) }
