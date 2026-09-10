# Scores the clean-up prompt on Apple Intelligence, the path that ships.
eval:
	Scripts/cleanup-eval/run.sh

# Scores the same cases on local GGUF models, e.g. make bench MODELS="a.gguf b.gguf".
bench:
	Scripts/llm-bench/run.sh $(MODELS)

.PHONY: eval bench
