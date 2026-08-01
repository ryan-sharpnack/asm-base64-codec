base64: src/main.asm
	nasm -f elf64 src/main.asm -o main.o
	ld main.o -o base64
	rm -f main.o

test: base64
	./test.sh

clean:
	rm -f main.o base64

.PHONY: test clean
