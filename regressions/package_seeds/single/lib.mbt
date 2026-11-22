pub struct Box[T] {
  v : T
}

pub fn[T] Box::new(v : T) -> Box[T] { { v } }

pub fn[T] Box::get(self : Box[T]) -> T { self.v }
