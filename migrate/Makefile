MODE ?= debug
T_DIR= build

SRC = .
ifneq ($(MODE), opt)
    CFLAGS+= -g3 -DDEBUG
	CPPFLAGS+= -g3 -DDEBUG
endif

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    SED_CMD = sed -i ""
else
    SED_CMD = sed -i
endif

.PHONY: clean doc 
all: doc

$(T_DIR)/readme.%: $(SRC)/readme.md | $(T_DIR)
	pandoc --pdf-engine=xelatex $< -o $@

$(T_DIR)/readme.txt: $(SRC)/readme.md | $(T_DIR)
	pandoc $< -o $@
	@$(SED_CMD) 's/\\\[/\[/g' $(T_DIR)/readme.txt
	@$(SED_CMD)"" 's/\\\]/\]/g' $(T_DIR)/readme.txt


doc: $(T_DIR)/readme.txt $(T_DIR)/readme.html $(T_DIR)/readme.docx $(T_DIR)/readme.pdf | $(T_DIR)

$(T_DIR):
	mkdir -p $(T_DIR)


clean:
	rm -f *~
	rm -rf $(T_DIR)
