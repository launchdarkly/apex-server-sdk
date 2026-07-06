SCRATCH_ORG=launchdarklyapexserversdk@example.com

push:
	sf project deploy start --ignore-conflicts --target-org $(SCRATCH_ORG)

test:
	sf apex run test --synchronous --target-org $(SCRATCH_ORG)

orgdelete:
	sf org delete scratch --no-prompt --target-org $(SCRATCH_ORG)

orgcreate:
	sf org create scratch --definition-file config/project-scratch-def.json --alias $(SCRATCH_ORG)