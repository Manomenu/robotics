from collections import deque

import numpy as np
from rclpy import init, shutdown, spin
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import Float32, String


class GraspMonitor(Node):
    def __init__(self):
        super().__init__('grasp_monitor')

        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT)

        self.create_subscription(Float32, 'vacuum_pressure', self.on_measurement, qos)

        self.pub = self.create_publisher(String, 'grasp_verdict', 10)
        self.frame = deque(maxlen=25)
        self.last_state = 'none'

    def on_measurement(self, msg: Float32):
        measure = msg.data
        self.frame.append(measure)

        if len(self.frame) < 25:
            return

        mean = np.mean(self.frame)

        # if self.last_state != 'empty':
        if is_at_level(mean, 0):
            self.publish_state_change('open')
        # self.last_state = 'empty'

        # if self.last_state != 'leak':
        if mean < -1 and mean > -58:
            self.publish_state_change('leak')
            # self.last_state = 'leak'

        # if self.last_state != 'sealed':
        if is_at_level(mean, -59):
            self.publish_state_change('sealed')
            # self.last_state = 'sealed'

    def publish_state_change(self, msg: str):
        str_msg = String()
        str_msg.data = '[state] ' + msg
        self.pub.publish(str_msg)


def is_at_level(value: float, level: float) -> bool:
    return level - 1 < value and value < level + 1


def main(args=None):
    init(args=args)

    node = GraspMonitor()
    spin(node)
    node.destroy_node()

    shutdown()


if __name__ == '__main__':
    main()
