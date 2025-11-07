CC      = gcc
CFLAGS  = -Wall -O2 -fPIC
LDFLAGS = -shared
LDLIBS = -ldl

SRC     = redirect_random.c
OBJ     = $(SRC:.c=.o)
TARGET  = redirect_random.so

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ)

distclean: clean
	rm -f $(TARGET)

.PHONY: all clean distclean

