-include .env

deploy anvil:
	@forge script script/DeployDSC.s.sol --rpc-url $(RPC_URL_ANVIL) --private-key $(PRIVATE_KEY_ANVIL) --broadcast

deploy sepolia:
	@forge script script/DeployDSC.s.sol --rpc-url $(RPC_URL_SEPOLIA) --private-key $(PRIVATE_KEY_SEPOLIA) --broadcast --verify --legacy