# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-31

### Added

- Initial release as Claude Code plugin
- **21 Specialized Agents**
  - Pipeline: requirements-analyst, plan-architect, plan-feedback, orchestrator
  - Execution: backend-dev, frontend-dev, ai-expert, git-ops, devops-engineer, database-expert, refactoring-expert, docs-writer
  - Quality: qa-planner, qa-executor, qa-healer, security-analyst, pr-reviewer, docs-reviewer, reporter, code-reviewer, performance-analyst
- **28 Skills**
  - Git: git_commit, git_branch, git_pr, git_issue, git_analyze
  - Python: python_setup, fastapi_setup, api_test_setup, rag_setup, python_best_practices
  - Java: spring_boot_setup, gradle_setup, jpa_entity, spring_best_practices
  - React: react_setup, nextjs_setup, component_generator, react_best_practices
  - AI/ML: mlflow_setup, langchain_setup
  - Infrastructure: docker_setup, alembic_migration
  - Quality: test_plan_template, test_runner, coverage_report, execution_report
  - Base: project_init, tdd_workflow
- Plugin manifest (`.claude-plugin/plugin.json`)
- MIT License
- Comprehensive documentation

### Features

- Automated agent pipeline for software development workflows
- Keyword-based automatic agent triggering
- Cross-LLM validation with Gemini CLI integration
- Quality assurance automation (code review, security analysis, testing)
- Git Flow compliance with git-ops agent

[1.0.0]: https://github.com/geonho-yeom/claude-code-setup/releases/tag/v1.0.0
