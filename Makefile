# NES Chaos - Makefile
# Uses ca65/ld65 from cc65 suite

# Try to find cc65 tools - check multiple locations
CC65_PATH = ../ninjaturdle_nes/tools/cc65/bin
CA65 = $(CC65_PATH)/ca65
LD65 = $(CC65_PATH)/ld65

# If cc65 is in PATH, you can use these instead:
# CA65 = ca65
# LD65 = ld65

# Config file
CFG = nrom.cfg

# Output
ROM = chaos.nes

# Sources
ASM_SRC = chaos.s
OBJ = $(ASM_SRC:.s=.o)

#------------------------------------------------------------------------------
# Default target
#------------------------------------------------------------------------------
.PHONY: all clean run

all: $(ROM)

#------------------------------------------------------------------------------
# Assemble
#------------------------------------------------------------------------------
%.o: %.s
	$(CA65) $< -o $@

#------------------------------------------------------------------------------
# Link
#------------------------------------------------------------------------------
$(ROM): $(OBJ) $(CFG)
	$(LD65) -C $(CFG) -o $@ $(OBJ)

#------------------------------------------------------------------------------
# Run in fceux (if installed)
#------------------------------------------------------------------------------
run: $(ROM)
	fceux $(ROM) &

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------
clean:
	rm -f $(OBJ) $(ROM)

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------
help:
	@echo "NES Chaos - Visual noise generator"
	@echo ""
	@echo "Targets:"
	@echo "  all   - Build chaos.nes (default)"
	@echo "  run   - Build and run in fceux"
	@echo "  clean - Remove build artifacts"
	@echo ""
	@echo "Requirements:"
	@echo "  - ca65/ld65 from cc65 suite"
	@echo "  - fceux (optional, for running)"

