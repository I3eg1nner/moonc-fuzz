enum E25 { A; B }
fn f(e : E25) -> Int { match e { A => 25 } }
fn main { println(f(A)) }
