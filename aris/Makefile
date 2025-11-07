SUBDIRS := scripts/examples opt/flux_helpers

# Default target: build everything
.PHONY: all $(SUBDIRS) clean

all: $(SUBDIRS)

# Rule: call make in each subdirectory
$(SUBDIRS):
	@$(MAKE) -C $@

# Clean everything
clean:
	@for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done

