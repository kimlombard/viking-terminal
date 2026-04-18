package main

import "core:fmt"
import "core:time"

main :: proc() {
    t := time.now()
    fmt.printf("Odin says the time is: %v\n", t)
}
