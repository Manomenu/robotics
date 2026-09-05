from rclpy.node import Node
from rclpy import init, spin, shutdown

class VacuumSensor(Node):
    def __init__(self):
        super().__init__('vacuum_sensor')

def main(args=None):
    init()

    node = VacuumSensor()
    spin(node)
    node.destroy_node()

    shutdown()

if __name__ == '__main__':
    main()
