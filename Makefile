SRCS := $(wildcard dedup*.rb)
OUT  := $(patsubst %.rb,%.txt,$(SRCS))
SUMM := $(patsubst %.rb,%.summary,$(SRCS))
RPTS := $(patsubst %.rb,%.stat,$(SRCS))

.PHONY: all clean

all: $(OUT) $(RPTS) $(SUMM)
clean:
	@rm $(RPTS) $(OUT)

%.txt: %.rb common.rb
	ruby $< > $@

# NOTE: $$ becomes $ after makefile escaping
%.stat: %.txt
	@echo "generate $@"
	@sed -ne '/vm00/,$$ p' $< > $@

%.summary: %.txt
	@echo "generate $@"
	@grep 'stats:' $< > $@

# ... view all stats inline
# pr -n02 -t -m dedup01.stat dedup02.stat
