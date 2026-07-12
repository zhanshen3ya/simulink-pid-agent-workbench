Feature: PID Controller Acceptance — Second-Order Demo
  As a control engineer
  I want the PID controller to meet time-domain specifications
  So that the closed-loop system is stable and performant

  Model: pid_ai_second_order_test
  Plant: G(s) = 1 / (s^2 + 1.2s + 1)
  Reference: Unit step input on port r
  Outputs: y (plant output), u (control signal)

  Background:
    Given I have a Simulink model named "pid_ai_second_order_test"
    And the model has a PID Controller block at "pid_ai_second_order_test/PID Controller"
    And the model has reference input port "r"
    And the model has output ports "y" and "u"
    And the model stop time is set to "10" seconds

  # ——————————————————————————————
  # Scenario 1: Default PID gains — baseline check
  # ——————————————————————————————
  Scenario: Default PID gains produce a stable response
    Given the PID Controller has gains P=1, I=0.2, D=0.01, N=100
    When I simulate the model with a unit step reference
    Then the simulation should complete successfully
    And the output y should be finite
    And the system should be stable
    And the overshoot should be less than 20 percent
    And the settling time should be less than 10 seconds

  # ——————————————————————————————
  # Scenario 2: Well-tuned PID — should pass all hard gates
  # ——————————————————————————————
  Scenario: Well-tuned PID meets all acceptance criteria
    Given the PID Controller has gains P=5, I=3, D=0.5, N=100
    When I simulate the model with a unit step reference
    Then the simulation should complete successfully
    And the output y should be finite
    And the system should be stable
    And the overshoot should be less than or equal to 10 percent
    And the settling time should be less than or equal to 5 seconds
    And the steady-state error should be less than or equal to 0.02

  # ——————————————————————————————
  # Scenario 3: Aggressive gains — should fail overshoot gate
  # ——————————————————————————————
  Scenario: Aggressive gains fail the overshoot criterion
    Given the PID Controller has gains P=80, I=80, D=0, N=10
    When I simulate the model with a unit step reference
    Then the simulation should complete successfully
    But the overshoot should be greater than 10 percent

  # ——————————————————————————————
  # Scenario 4: Zero integral gain — should fail steady-state error gate
  # ——————————————————————————————
  Scenario: Zero integral gain fails steady-state error criterion
    Given the PID Controller has gains P=2, I=0, D=0.5, N=100
    When I simulate the model with a unit step reference
    Then the simulation should complete successfully
    But the steady-state error should be greater than 0.02

  # ——————————————————————————————
  # Scenario 5: Control signal stays within bounds
  # ——————————————————————————————
  Scenario: Control signal remains bounded
    Given the PID Controller has gains P=5, I=3, D=0.5, N=100
    When I simulate the model with a unit step reference
    Then the maximum absolute control signal should be less than 200
    And the control energy should be finite

  # ——————————————————————————————
  # Scenario 6: Weighted score is computed correctly
  # ——————————————————————————————
  Scenario: Weighted score reflects overall performance
    Given the PID Controller has gains P=5, I=3, D=0.5, N=100
    When I simulate the model with a unit step reference
    Then the simulation should complete successfully
    And the weighted score should be finite
    And the weighted score should be less than 100