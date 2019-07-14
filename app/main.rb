class FlyingSheepHunt
  attr_accessor :grid, :inputs, :game, :outputs

  SPAWN_INCREASE = 0.5
  SPEED_INCREASE = 0.1

  def tick
    defaults
    render
    calc
    input
  end

  def defaults
    game.started ||= false
    game.fired ||= false
    game.x ||= 0
    game.y ||= 0
    game.xhair_box ||= [game.x + 16, game.y + 16, 2, 2]
    game.sheep_min_speed ||= 1
    game.sheep_min_spawn_rate ||= 60.0
    game.sheep_spawn_countdown ||= random_spawn_countdown game.sheep_min_spawn_rate
    game.sheeps ||= []
    game.killed_sheeps ||= []
    game.bloods ||= []
    game.killed_sheeps_count ||= 0
    game.life_count ||= 10
    game.top_score ||= 0
  end

  def reset
    game.started = false
    game.fired = false
    game.sheep_min_speed = 1
    game.sheep_min_spawn_rate = 60.0
    game.sheep_spawn_countdown = random_spawn_countdown game.sheep_min_spawn_rate
    game.sheeps = []
    game.killed_sheeps = []
    game.bloods = []
    game.killed_sheeps_count = 0
    game.life_count = 10
  end

  def random_spawn_countdown(minimum)
    10.randomize(:ratio, :sign).to_i + minimum
  end

  def render_sheep
    outputs.sprites << game.sheeps.map do |z|
      # last param seems to change dir?
      z.sprite = [z.x, z.y, 64, 64, "sprites/sheep.png", 0, 255, 255, 255, 255, 0, 0, 64, 64, z.dir == 1] # 4 * 3, 8 * 3, animation_sprite(z)]
      z.sprite
    end
  end

  def render_bloods(sprite_size = 6)
    outputs.sprites << game.bloods.map do |p|
      apply_round_finished_alpha [sprite_size.to_square(p.x, p.y),
                                  "sprites/flame.png", 0,
                                  p.max_alpha * p.created_at.ease(p.lifetime, :flip)]
    end
  end

  def render
    outputs.sprites << [0, 0, 1280, 720, "sprites/background.png"]

    if game.started
      render_sheep
      game.player_sprite = [
        game.x,
        game.y,
        32, 32, "sprites/crosshair.png",
      ]
      outputs.sprites << game.player_sprite
      render_bloods

      outputs.labels << [grid.rect.w - 100, grid.rect.h - 10,
                         "Score: #{game.killed_sheeps_count}", 0, 0, 255, 255, 255]

      outputs.labels << [grid.rect.w - 100, grid.rect.h - 50,
                         "Lives: #{game.life_count}", 0, 0, 255, 255, 255]
    else
      #if game.top_score > 0
      outputs.labels << [580, 370, "Top Score: #{game.top_score}", 0, 0, 255, 255, 255]

      #end

      outputs.labels << [580, 400, "Click to start", 0, 0, 255, 255, 255]
    end
  end

  def calc_spawn_sheep
    if game.sheep_spawn_countdown > 0
      game.sheep_spawn_countdown -= 1
      return
    end

    game.sheeps << game.new_entity(:sheep) do |z|
      if rand > 0.5
        z.x = 0 - 64
        z.dir = 1
      else
        z.x = 1280 + 64
        z.dir = -1
      end
      z.y = (grid.rect.h - 64).randomize(:ratio)
      z.speed = game.sheep_min_speed
    end

    game.sheep_spawn_countdown = random_spawn_countdown game.sheep_min_spawn_rate
    game.sheep_min_spawn_rate -= SPAWN_INCREASE
    game.sheep_min_spawn_rate = game.sheep_min_spawn_rate.greater(0)
    game.sheep_min_speed += SPEED_INCREASE
  end

  def calc_move_sheep
    game.sheeps.each do |z|
      z.x += z.speed * z.dir #z.x.towards((z.dir * (z.x + z.speed)), 10)# z.speed)
    end

    current = game.sheeps.length

    game.sheeps = game.sheeps.reject do |z|
      if z.dir == 1
        z.x > (grid.rect.w + 64)
      else
        z.x < (grid.rect.x - 64)
      end
    end

    rejected = current - game.sheeps.length

    game.life_count -= rejected
    if rejected > 0 && game.started
      outputs.sounds << "sounds/death.wav"
    end
  end

  def calc_kill_sheep
    if !game.fired
      return
    end

    outputs.sounds << "sounds/shot.wav"
    killed_this_frame = game.sheeps.find_all { |z| game.xhair_box.inside_rect? z.sprite }
    game.killed_sheeps_count += killed_this_frame.length
    game.sheeps = game.sheeps - killed_this_frame
    game.killed_sheeps += killed_this_frame

    killed_this_frame.each do |z|
      z.death_at = game.tick_count
      create_explosion! :blood, z, 30, 10, 30 #, 255 #s.max_alpha
    end

    game.killed_sheeps = game.killed_sheeps.reject { |z| game.tick_count - z.death_at > 30 }
  end

  def calc_bloods
    game.bloods =
      game.bloods
        .reject(&:old?)
        .map do |p|
        p.speed *= 0.9
        p.y += p.angle.vector_y(p.speed) - 1
        p.x += p.angle.vector_x(p.speed)
        p
      end
  end

  def calc_game_over
    if game.life_count <= 0
      if game.killed_sheeps_count > game.top_score
        game.top_score = game.killed_sheeps_count
      end
      game.started = false
    end
  end

  def calc
    #puts "d=#{game.sheep_min_spawn_rate};s=#{game.sheep_min_speed}"
    calc_spawn_sheep
    calc_move_sheep
    calc_kill_sheep
    calc_bloods
    calc_game_over
  end

  def input
    game.fired = false
    if inputs.mouse.click
      if !game.started
        reset
        game.started = true
      end
      game.fired = true
    end
    if inputs.mouse.moved
      game.x = inputs.mouse.position.x - 16
      game.y = inputs.mouse.position.y - 16
      game.xhair_box = [game.x + 16, game.y + 16, 2, 2]
    end
  end

  def create_explosion!(type, entity, blood_count, max_speed, lifetime, max_alpha = 255)
    blood_count.times do
      game.bloods << game.new_entity(type,
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
    return entity unless game.round_finished_debounce
    entity.a *= game.round_finished_debounce.percentage_of(2.seconds)
    return entity
  end
end

$flying_sheep_hunt = FlyingSheepHunt.new

def tick(args)
  $flying_sheep_hunt.inputs = args.inputs
  $flying_sheep_hunt.game = args.game
  $flying_sheep_hunt.outputs = args.outputs
  $flying_sheep_hunt.grid = args.grid
  $flying_sheep_hunt.tick
end
