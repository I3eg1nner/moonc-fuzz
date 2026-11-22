enum E21 { A; B }
fn f(e : E21) -> Int { match e { A => 21 } }
fn main { println(f(A)) }
