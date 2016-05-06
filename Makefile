PROJECT = bson

DIALYZER = dialyzer

all: clean compile xref eunit

clean compile xref eunit:
	@./rebar $@

# Dialyzer
.$(PROJECT).plt: 
	@$(DIALYZER) --build_plt --output_plt .$(PROJECT).plt \
		--apps erts kernel stdlib syntax_tools crypto

clean-plt: 
	    rm -f .$(PROJECT).plt

build-plt: clean-plt .$(PROJECT).plt

dialyze: .$(PROJECT).plt
	    @$(DIALYZER) -I include --src -r src --plt .$(PROJECT).plt --no_native \
			        -Werror_handling -Wrace_conditions -Wunmatched_returns

.PHONY: clean-plt build-plt dialyze


