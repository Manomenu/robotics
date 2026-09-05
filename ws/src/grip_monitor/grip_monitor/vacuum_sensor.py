from rclpy.node import Node
from rclpy import init, spin, shutdown
from std_msgs.msg import Float32
from rcl_interfaces.msg._parameter_event import ParameterEvent

class VacuumSensor(Node):
    def __init__(self):
        super().__init__('vacuum_sensor')
        self.pub = self.create_publisher(Float32, 'vacuum_pressure', 10)
        self.create_timer(1.0/50, self.tick)

    def tick(self):
        msg = Float32()
        msg.data = -58.0

        self.pub.publish(msg)


def main(args=None):
    init(args=args)

    node = VacuumSensor()
    spin(node)
    node.destroy_node()

    shutdown()

if __name__ == '__main__':
    main()
