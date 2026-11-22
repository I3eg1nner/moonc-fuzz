enum E10 { A; B }
fn f(e : E10) -> Int { match e { A => 10 } }
fn main { println(f(A)) }
