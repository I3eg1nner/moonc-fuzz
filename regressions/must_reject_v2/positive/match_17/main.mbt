enum E17 { A; B }
fn f(e : E17) -> Int { match e { A => 17 } }
fn main { println(f(A)) }
