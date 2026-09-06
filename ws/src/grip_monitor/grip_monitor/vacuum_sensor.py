from random import gauss

from rclpy import init, shutdown, spin
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import Float32


class VacuumSensor(Node):
    def __init__(self):
        super().__init__('vacuum_sensor')
        self.declare_parameter('state', 'empty')
        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.pub = self.create_publisher(Float32, 'vacuum_pressure', qos)
        self.create_timer(1.0 / 50, self._tick)

    def _tick(self):
        noise = gauss(0, 0.5)
        state_value = self._get_state_value()

        msg = Float32()
        msg.data = state_value + noise

        self.pub.publish(msg)

    def _get_state_value(self) -> float:
        state = self.get_parameter('state').value

        if state == 'empty':
            return 0.0
        if state == 'sealed':
            return -59.0
        if state == 'leak':
            return -20.0

        raise RuntimeError('Invalid state')


def main(args=None):
    init(args=args)

    node = VacuumSensor()
    spin(node)
    node.destroy_node()

    shutdown()


if __name__ == '__main__':
    main()
