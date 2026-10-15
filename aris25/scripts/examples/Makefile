MPICC   ?= mpiicc          
CFLAGS  ?= -O2 -Wall -Wextra
LDFLAGS ?=
TARGET  ?= mpi_hello
SRC     ?= mpi_hello.c


.PHONY: all clean 

all: $(TARGET)

$(TARGET): $(SRC)
	$(MPICC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	$(RM) $(TARGET)
