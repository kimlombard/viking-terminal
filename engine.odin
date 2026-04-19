package main

import "core:fmt"
import "core:time"
import "core:math/rand"

Candle :: struct {
	time:  i64,
	open:  f64,
	high:  f64,
	low:   f64,
	close: f64,
	volume: f64,
}

main :: proc() {
	// Starting price
	price := 100.0

	for {
		c: Candle
		c.time  = time.to_unix_nanoseconds(time.now()) / 1_000_000_000
		c.open  = price
		c.high  = price
		c.low   = price
		c.volume = 0.0 

		// Simulate 5 "sub-ticks" to build one candle body
		for _ in 0..<5 {
			move := (rand.float64() - 0.5)
			price += move
			c.volume += rand.float64() * 100 // Add random volume per tick
			if price > c.high do c.high = price
			if price < c.low  do c.low  = price
			time.sleep(200 * time.Millisecond)
		}
		c.close = price

		// Send Format: candle:time,open,high,low,close,volume
		fmt.printf("candle:%v,%.2f,%.2f,%.2f,%.2f,%.2f\n", c.time, c.open, c.high, c.low, c.close, c.volume)
	}
}
