module MLib (pub) where
pub :: Int -> Int
pub x = hidden x + 1
hidden :: Int -> Int
hidden = (* 2)
