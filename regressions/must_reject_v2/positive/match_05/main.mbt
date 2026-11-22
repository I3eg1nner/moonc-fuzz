enum E5 { A; B }
fn f(e : E5) -> Int { match e { A => 5 } }
fn main { println(f(A)) }
