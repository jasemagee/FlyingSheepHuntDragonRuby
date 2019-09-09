class FlyingSheepHunt
  attr_accessor :grid, :inputs, :state, :outputs

  SPAWN_INCREASE = 0.5
  SPEED_INCREASE = 0.1

  def tick
    defaults
    render
    calc
    input
  end

  def defaults
    state.started ||= false
    state.fired ||= false
    state.x ||= 0
    state.y ||= 0
    state.xhair_box ||= [state.x + 16, state.y + 16, 2, 2]
    state.sheep_min_speed ||= 1
    state.sheep_min_spawn_rate ||= 60.0
    state.sheep_spawn_countdown ||= random_spawn_countdown state.sheep_min_spawn_rate
    state.sheeps ||= []
    state.killed_sheeps ||= []
    state.bloods ||= []
    state.killed_sheeps_count ||= 0
    state.life_count ||= 10
    state.top_score ||= 0
  end

  def reset
    state.started = false
    state.fired = false
    state.sheep_min_speed = 1
    state.sheep_min_spawn_rate = 60.0
    state.sheep_spawn_countdown = random_spawn_countdown state.sheep_min_spawn_rate
    state.sheeps = []
    state.killed_sheeps = []
    state.bloods = []
    state.killed_sheeps_count = 0
    state.life_count = 10
  end

  def random_spawn_countdown(minimum)
    10.randomize(:ratio, :sign).to_i + minimum
  end

  def render_sheep
    outputs.sprites << state.sheeps.map do |z|
      # last param seems to change dir?
      z.sprite = [z.x, z.y, 64, 64, "sprites/sheep.png", 0, 255, 255, 255, 255, 0, 0, 64, 64, z.dir == 1] # 4 * 3, 8 * 3, animation_sprite(z)]
      z.sprite
    end
  end

  def render_bloods(sprite_size = 6)
    outputs.sprites << state.bloods.map do |p|
      apply_round_finished_alpha [sprite_size.to_square(p.x, p.y),
                                  "sprites/flame.png", 0,
                                  p.max_alpha * p.created_at.ease(p.lifetime, :flip)]
    end
  end

  def render
    outputs.sprites << [0, 0, 1280, 720, "sprites/background.png"]

    if state.started
      render_sheep
      state.player_sprite = [
        state.x,
        state.y,
        32, 32, "sprites/crosshair.png",
      ]
      outputs.sprites << state.player_sprite
      render_bloods

      outputs.labels << [grid.rect.w - 100, grid.rect.h - 10,
                         "Score: #{state.killed_sheeps_count}", 0, 0, 255, 255, 255]

      outputs.labels << [grid.rect.w - 100, grid.rect.h - 50,
                         "Lives: #{state.life_count}", 0, 0, 255, 255, 255]
    else
      #if state.top_score > 0
      outputs.labels << [580, 370, "Top Score: #{state.top_score}", 0, 0, 255, 255, 255]

      #end

      outputs.labels << [580, 400, "Click to start", 0, 0, 255, 255, 255]
    end
  end

  def calc_spawn_sheep
    if state.sheep_spawn_countdown > 0
      state.sheep_spawn_countdown -= 1
      return
    end

    state.sheeps << state.new_entity(:sheep) do |z|
      if rand > 0.5
        z.x = 0 - 64
        z.dir = 1
      else
        z.x = 1280 + 64
        z.dir = -1
      end
      z.y = (grid.rect.h - 64).randomize(:ratio)
      z.speed = state.sheep_min_speed
    end

    state.sheep_spawn_countdown = random_spawn_countdown state.sheep_min_spawn_rate
    state.sheep_min_spawn_rate -= SPAWN_INCREASE
    state.sheep_min_spawn_rate = state.sheep_min_spawn_rate.greater(0)
    state.sheep_min_speed += SPEED_INCREASE
  end

  def calc_move_sheep
    state.sheeps.each do |z|
      z.x += z.speed * z.dir #z.x.towards((z.dir * (z.x + z.speed)), 10)# z.speed)
    end

    current = state.sheeps.length

    state.sheeps = state.sheeps.reject do |z|
      if z.dir == 1
        z.x > (grid.rect.w + 64)
      else
        z.x < (grid.rect.x - 64)
      end
    end

    rejected = current - state.sheeps.length

    state.life_count -= rejected
    if rejected > 0 && state.started
      outputs.sounds << "sounds/death.wav"
    end
  end

  def calc_kill_sheep
    if !state.fired
      return
    end

    outputs.sounds << "sounds/shot.wav"
    killed_this_frame = state.sheeps.find_all { |z| state.xhair_box.inside_rect? z.sprite }
    state.killed_sheeps_count += killed_this_frame.length
    state.sheeps = state.sheeps - killed_this_frame
    state.killed_sheeps += killed_this_frame

    killed_this_frame.each do |z|
      z.death_at = state.tick_count
      create_explosion! :blood, z, 30, 10, 30 #, 255 #s.max_alpha
    end

    state.killed_sheeps = state.killed_sheeps.reject { |z| state.tick_count - z.death_at > 30 }
  end

  def calc_bloods
    state.bloods =
      state.bloods
        .reject(&:old?)
        .map do |p|
        p.speed *= 0.9
        p.y += p.angle.vector_y(p.speed) - 1
        p.x += p.angle.vector_x(p.speed)
        p
      end
  end

  def calc_state_over
    if state.life_count <= 0
      if state.killed_sheeps_count > state.top_score
        state.top_score = state.killed_sheeps_count
      end
      state.started = false
    end
  end

  def calc
    #puts "d=#{state.sheep_min_spawn_rate};s=#{state.sheep_min_speed}"
    calc_spawn_sheep
    calc_move_sheep
    calc_kill_sheep
    calc_bloods
    calc_state_over
  end

  def input
    state.fired = false
    if inputs.mouse.click
      if !state.started
        reset
        state.started = true
      end
      state.fired = true
    end
    if inputs.mouse.moved
      state.x = inputs.mouse.position.x - 16
      state.y = inputs.mouse.position.y - 16
      state.xhair_box = [state.x + 16, state.y + 16, 2, 2]
    end
  end

  def create_explosion!(type, entity, blood_count, max_speed, lifetime, max_alpha = 255)
    blood_count.times do
      state.bloods << state.new_entity(type,
                                       { angle: 360.randomize(:ratio),
                                         speed: max_speed.randomize(:ratio),
                                         lifetime: lifetime,
                                         x: entity.x + 32,
                                         y: entity.y + 32,
                                         max_alpha: max_alpha })
    end
  end

  def apply_round_finished_alpha(entity)
    entity = entity.flatten
    return entity unless state.round_finished_debounce
    entity.a *= state.round_finished_debounce.percentage_of(2.seconds)
    return entity
  end
end

$flying_sheep_hunt = FlyingSheepHunt.new

def tick(args)
  $flying_sheep_hunt.inputs = args.inputs
  $flying_sheep_hunt.state = args.state
  $flying_sheep_hunt.outputs = args.outputs
  $flying_sheep_hunt.grid = args.grid
  $flying_sheep_hunt.tick
end
