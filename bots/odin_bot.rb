require 'rtanque'
require 'rtanque/point'

class OdinBot < RTanque::Bot::Brain
  NAME = 'OdinBot'
  include RTanque::Bot::BrainHelper
   
   CIRCLE_RADIUS = 75
   
   MAX_PAST_POSITIONS = 40
   MAX_VECTORS = 40
   
   BOT_MOVEMENT_RADIUS = 115
   MAX_DISTANCE_FROM_WALL = BOT_MOVEMENT_RADIUS + 75
   
   # Positive Turn direction is clock-wise
   
  def tick!
    @lastReverseHeading ||= 125
    @turnDirection ||= 1
    @radarDirection ||= 1
    @foundTarget ||= false
    @targets ||= Hash.new
    
    reflections = self.sensors.radar
    updateTargets reflections
    
    drive
    
    reflection = nearest_reflection reflections
    if reflection
      
      target = @targets[reflection.name]
      
      # Fire at target
      fire_upon target
      
      # TODO: Do
      # Update radarDirection based on where the target is from heading
      @radarDirection = 1
      
      # Focus radar at closest reflection
      self.command.radar_heading = reflection.heading
    else
      # Look for targets
      scanForTargets
    end
  end
  
  def drive
    self.command.speed = 3.0
    
    center = getBotCircleCenter @turnDirection
    if isPointNearWall center, MAX_DISTANCE_FROM_WALL
      
      @wall = nil
      
      # Drive in circles but stay near wall
      self.command.heading = self.sensors.heading + @turnDirection * MAX_BOT_ROTATION
      
      reverseHeading
    elsif !isCircleInsideArena? center, BOT_MOVEMENT_RADIUS
      unless @wall
        @wall = getNearestWall
      end
      self.command.heading = self.sensors.position.heading(@wall) + Math::PI
    else
      # Drive to wall
      unless @wall
        @wall = getNearestWall
      end
      self.command.heading = self.sensors.position.heading @wall
    end
  end
  
  def reverseHeading
    @lastReverseHeading = @lastReverseHeading - 1
    newBotCenter = getBotCircleCenter @turnDirection * -1
    if isPointBetweenWallRadius? newBotCenter or @lastReverseHeading < -300
      if @lastReverseHeading <= 0
        @turnDirection = @turnDirection * -1
        @lastReverseHeading = rand(50) + 25
      end
    end
  end
  
  def getBotCircleCenter turnDirection
    self.sensors.position.move (self.sensors.heading + (turnDirection * Math::PI / 2)), BOT_MOVEMENT_RADIUS, false
  end
  
  def isPointNearWall point, distance
    (self.arena.width - point.x <= distance) || (point.x <= distance) || (self.arena.height - point.y <= distance) || (point.y <= distance)
  end
  
  def isPointBetweenWallRadius? point
    (((self.arena.width - point.x >= BOT_MOVEMENT_RADIUS) && (self.arena.width - point.x < MAX_DISTANCE_FROM_WALL)) ||
    ((self.arena.width + point.x >= BOT_MOVEMENT_RADIUS) && (self.arena.width + point.x < MAX_DISTANCE_FROM_WALL)) ||
    ((self.arena.height - point.y >= BOT_MOVEMENT_RADIUS) && (self.arena.height - point.y < MAX_DISTANCE_FROM_WALL)) ||
    ((self.arena.height + point.y >= BOT_MOVEMENT_RADIUS) && (self.arena.height + point.y < MAX_DISTANCE_FROM_WALL))) && 
    isCircleInsideArena?(point, BOT_MOVEMENT_RADIUS)
  end
  
  def isCircleInsideArena? point, radius
    
    northPoint = RTanque::Point.new(point.x, point.y - radius, self.arena)
    southPoint = RTanque::Point.new(point.x, point.y + radius, self.arena)
    westPoint = RTanque::Point.new(point.x - radius, point.y, self.arena)
    eastPoint = RTanque::Point.new(point.x + radius, point.y, self.arena)
    
    isPointInsideArena(northPoint) && isPointInsideArena(southPoint) && isPointInsideArena(westPoint) && isPointInsideArena(eastPoint)
  end
  
  def isPointInsideArena point
    point.x >= 0 && point.y >= 0 && point.x <= self.arena.width && point.y <= self.arena.height
  end
  
  def getNearestWall
    eastWall = RTanque::Point.new self.arena.width, self.sensors.position.y, self.arena
    westWall = RTanque::Point.new 0, self.sensors.position.y, self.arena
    northWall = RTanque::Point.new self.sensors.position.x, 0, self.arena
    southWall = RTanque::Point.new self.sensors.position.x, self.arena.height, self.arena
    
    closestPoint = eastWall
    distance = self.sensors.position.distance eastWall
    
    westDistance = self.sensors.position.distance westWall
    if westDistance < distance
      closestPoint = westWall
      distance = westDistance
    end
    
    northDistance = self.sensors.position.distance northWall
    if northDistance < distance
      closestPoint = northWall
      distance = northDistance
    end
    
    southDistance = self.sensors.position.distance southWall
    if southDistance < distance
      closestPoint = southWall
      distance = southDistance
    end
    
    closestPoint
  end
  
  def updateTargets targetPositions
    currentTick = self.sensors.ticks
    
    # Update the targets we did see
    targetPositions.each do |targetPosition|
      targetName = targetPosition.name
      unless @targets.has_key? targetName
        @targets.store targetName, Target.new(targetName)
      end
      @targets[targetName].addPosition self.sensors.position.move(targetPosition.heading, targetPosition.distance, true), currentTick
    end
    
    # We didn't see these targets so mark it in our data
    @targets.each do |name, target|
      unless target.hasAddedPosition? currentTick
        target.addPosition nil, currentTick
      end
    end
    
  end
  
  def nearest_reflection reflections
    enemys = Array.new
    reflections.each do |reflection| 
      #unless reflection.name == NAME
        enemys.push reflection
      #end
    end
    enemys.min { |a,b| a.distance <=> b.distance }
  end
  
  def scanForTargets
    self.command.radar_heading = self.sensors.radar_heading + MAX_RADAR_ROTATION * @radarDirection
    self.command.turret_heading = self.sensors.radar_heading
  end
  
  def fire_upon target
    
    # We fire after we have moved
    positionWhenFiring = self.sensors.position.move self.sensors.heading, self.sensors.speed
    
    # Use maximum fire power since it moves fastest. This means we don't have to predict as far into the
    # future which will increase the chances we are correct
    firePower = MAX_FIRE_POWER
    
    # In the case the target is not track-able use the target itself as the future target for aiming our turret
    futureTarget = target
    
    if target.isTrackable?
      
      # Calculate future target by getting the target when the bullet should hit
      futureTarget = getFutureTargetWhenBulletHits target, positionWhenFiring, firePower
      
      # Since we are firing at full power we fire very slowly so be conservative and only fire if our
      # current turret heading will hit the future target
      if willBulletHit? futureTarget, positionWhenFiring, self.sensors.turret_heading
        self.command.fire firePower
      end
    end
    
    # Point turret at future target
    self.command.turret_heading = positionWhenFiring.heading futureTarget.position
    
  end
  
  def getFutureTargetWhenBulletHits target, currentPosition, firePower
    
    # Ensure we use a valid firePower
    botFirePower = [firePower, MAX_FIRE_POWER].min
    
    # A shell starts its life at the end of the turret (not the middle of our bot)
    shellTravelDistance = RTanque::Bot::Turret::LENGTH
    
    # Calculate speed of shell (or distance travled per tick)
    shellSpeed =  RTanque::Shell::SHELL_SPEED_FACTOR * botFirePower
    
    futureTarget = target
    ticks = 0
    
    # This algorithm tries to simulate where the target will be when a shell fired at 'firePower' would hit it if
    # aimed at the target's future position. We do this by only keeping track of how far the shell has traveled and
    # use data collected about the target to predict where it will move. Moving both the shell and the target 1 tick 
    # each iteration we then quit when the distance the shell has traveled is greater than the distance between our
    # bot and the future target (i.e. the shell has passed through or hit the enemy)
    begin
      ticks = ticks + 1
      
      # Move the bullet 
      shellTravelDistance = shellTravelDistance + shellSpeed
      
      # Using the collected data on the target move the target and generate a new target (new speed/heading/position)
      futureTarget = futureTarget.move
      
    end while RTanque::Point.distance(currentPosition, futureTarget.position) >= shellTravelDistance
    
    # TODO To be technically correct we should move the futureTarget back a bit since the bullet likely traveled past at most shellSpeed * 1 tick
    
    futureTarget
  end
  
  def willBulletHit? futureTarget, currentPosition, turretHeading
    # Here we check if from the current position and with the turret heading a shell would (or line) would intersect
    # the radius of the bot or future target
    Math.sin(turretHeading.delta(currentPosition.heading futureTarget.position)) * RTanque::Point.distance(currentPosition, futureTarget.position) <= RTanque::Bot::RADIUS 
  end
  
  class Target
    
    attr_reader :botName
    attr_reader :position
    attr_reader :heading
    
    def initialize botName, position=nil, heading=nil, vectors=Array.new, moveCount=0
      @botName = botName
      @position = position
      @heading = heading
      @lastTick = nil
      @vectors = vectors
      @moveCount = moveCount
    end
    
    def addPosition position, tick
      if @vectors.size > MAX_VECTORS
        @vectors.delete_at 0
      end
      
      if @position and position
        newVector = PositionedVector.fromPositions @position, position
        @vectors.push newVector
        @heading = newVector.heading
      else
        @vectors.push nil
      end
      
      @position = position
      @lastTick = tick
    end
    
    # Used to see if we have added a position or not so we can update targets we didn't see with nil values
    def hasAddedPosition? tick
      tick == @lastTick
    end
    
    def isTrackable?
      # We must have at least 2 vectors to be track-able so we can calculate a change in heading.
      # We must also know last known position.
      !@position.nil? and !@heading.nil? and vectors.size >= 2
    end
    
    def vectors
      @vectors.select {|vector| !vector.nil? }.reverse
    end
    
    def move
      # Prediction algorithm used to figure out the next target if moved forward 1 tick in time
      
      # Number of vectors to use in our calculations
      # The idea here is the further out we need to predict the more data we should include
      numberOfVectorsToUse = @moveCount + 1
      
      # Only use numberOfVectorsToUse vectors
      availableVectors = vectors[0..numberOfVectorsToUse]
      
      # Calculate the average change in heading and speed from the available vectors
      # Not sure why but we have to flip this calculation
      changeInHeading = (PositionedVector.changeInHeading availableVectors) * -1.0
      speed = PositionedVector.averageSpeed availableVectors
      
      # Calculate new heading and position from previously calculated results
      newHeading = RTanque::Heading.new heading.to_f + changeInHeading
      newPosition = position.move newHeading, speed, true
      
      # Build new target with new position/heading and increasing the moveCount
      Target.new botName, newPosition, newHeading, @vectors, @moveCount + 1
      
    end
    
  end
  
  class PositionedVector
    
    attr_reader :position
    attr_reader :heading
    attr_reader :speed
    
    def self.fromPositions position1, position2
      heading = position1.heading position2
      speed = RTanque::Point.distance position1, position2
      
      PositionedVector.new position1, heading, speed
    end
    
    def self.averageSpeed vectors
      totalSpeed = 0.0
      
      vectors.each do |vector|
        totalSpeed = totalSpeed + vector.speed
      end
      
      totalSpeed / vectors.size
    end
    
    def self.changeInHeading vectors
      changeInHeading = 0.0
      previousVector = vectors.first
      
      vectors[1..vectors.size].each do |currentVector|
        changeInHeading = changeInHeading + previousVector.heading.delta(currentVector.heading)
        previousVector = currentVector
      end
      
      changeInHeading / (vectors.size - 1)
    end
    
    def initialize position, heading, speed
      @position = position
      @heading = heading
      @speed = speed
    end
    
  end
  
end
