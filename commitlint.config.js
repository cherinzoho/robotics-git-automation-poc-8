module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Scope is mandatory on every commit
    'scope-empty': [2, 'never'],

    // Allowed types: feat fix refactor test sim ci docs chore build
    // Add custom types to COMMIT_TYPES in tools/project.env
    'type-enum': [2, 'always', [
      'feat',
      'fix',
      'refactor',
      'test',
      'sim',
      'ci',
      'docs',
      'chore',
      'build',
    ]],

    // Allowed scopes — edit COMMIT_SCOPES in tools/project.env
    // Format in project.env: scope:description
    'scope-enum': [2, 'always', [
      'arm', // robotic arm
      'amr', // autonomous mobile robot
      'humanoid', // humanoid robot
      'sim', // Gazebo simulation
      'nav', // navigation stack
      'slam', // SLAM and mapping
      'perception', // sensor processing
      'control', // control systems
      'hw', // hardware and firmware
      'sdk', // SDK and interfaces
      'infra', // server infrastructure
      'docs', // documentation
      'ci', // CI/CD pipeline files
      'repo', // repository config files
    ]],

    // Subject max 72 characters
    // Edit COMMIT_SUBJECT_MAX_LENGTH in tools/project.env
    'subject-max-length': [2, 'always', 72],

    // subject-case disabled — technical acronyms (ROS2, SLAM, AMR) conflict
    // with all built-in case rules. Convention enforced via code review.
    'subject-case': [0],

    // NOTE: A space after the colon is required by the Conventional Commits
    // specification. This is enforced by the commit-msg hook before
    // commitlint runs. If you see "fix stuff" being rejected it is because
    // the message has no type/scope, not a spacing issue.
  },
};
