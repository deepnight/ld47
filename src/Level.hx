class Level extends dn.Process {
	public var game(get,never) : Game; inline function get_game() return Game.ME;
	public var fx(get,never) : Fx; inline function get_fx() return Game.ME.fx;

	public var cWid(get,never) : Int; inline function get_cWid() return level.l_Collisions.cWid;
	public var cHei(get,never) : Int; inline function get_cHei() return level.l_Collisions.cHei;

	public var level : World_Level;

	var marks : Map< LevelMark, Map<Int,Bool> > = new Map();
	var invalidated = true;

	var lightWrapper : h2d.Object;
	var front : h2d.TileGroup;
	var details : h2d.TileGroup;
	var walls : h2d.TileGroup;
	var bg : h2d.TileGroup;
	var dark : h2d.TileGroup;
	var customs : h2d.TileGroup;
	public var burn : h2d.TileGroup;
	var extraCollMap : Map<Int,Bool> = new Map();

	public var haloMask : h2d.Graphics;

	public var fakeLight(default,set) = 1.0;


	public function new(l:World_Level) {
		super(Game.ME);
		createRootInLayers(Game.ME.scroller, Const.DP_BG);
		level = l;

		var sourceTile = l.l_Collisions.tileset.getAtlasTile();

		front = new h2d.TileGroup(sourceTile);
		game.scroller.add(front, Const.DP_FRONT);

		dark = new h2d.TileGroup(sourceTile, root);

		lightWrapper = new h2d.Object(root);
		bg = new h2d.TileGroup(sourceTile, lightWrapper);
		walls = new h2d.TileGroup(sourceTile, lightWrapper);
		details = new h2d.TileGroup(Assets.tiles.tile, lightWrapper);

		customs = new h2d.TileGroup(Assets.tiles.tile, root);

		burn = new h2d.TileGroup(sourceTile, lightWrapper);
		burn.blendMode = Add;
		burn.filter = new h2d.filter.Group([
			new h2d.filter.Bloom(4, 1, 16),
			// new h2d.filter.Blur(8),
		]);

		haloMask = new h2d.Graphics(lightWrapper);
		haloMask.beginFill(0xffffff);
		haloMask.drawCircle(0,0,Const.GRID*5);
		haloMask.visible = false;

		// Marking
		for(cy in 0...cHei)
		for(cx in 0...cWid) {
			if( !hasCollision(cx,cy) && !hasCollision(cx,cy-1) ) {
				if( hasCollision(cx+1,cy) && !hasCollision(cx+1,cy-1) )
					setMarks(cx,cy, [Grab,GrabRight]);

				if( hasCollision(cx-1,cy) && !hasCollision(cx-1,cy-1) )
					setMarks(cx,cy, [Grab,GrabLeft]);
			}

			if( !hasCollision(cx,cy) && hasCollision(cx,cy+1) ) {
				if( hasCollision(cx+1,cy) || !hasCollision(cx+1,cy+1) )
					setMarks(cx,cy, [PlatformEnd,PlatformEndRight]);
				if( hasCollision(cx-1,cy) || !hasCollision(cx-1,cy+1) )
					setMarks(cx,cy, [PlatformEnd,PlatformEndLeft]);
			}
		}
	}

	public function attachMainEntities() {
		var e = level.l_Entities.all_Hero[0];
		game.hero = new en.Hero(e);
		game.hero.yr = 0.4;
		game.hero.dx = 0.1;
		game.hero.dy = -0.1;


		for(e in level.l_Entities.all_Vortex)
			new en.Vortex(e);

		for(e in level.l_Entities.all_Text)
			new en.Text(e);

		for(e in level.l_Entities.all_Vault)
			new en.Vault(e);

		for(e in level.l_Entities.all_Trigger)
			new en.Trigger(e);

		for(e in level.l_Entities.all_Door)
			new en.Door(e);

		for( e in level.l_Entities.all_Item ) {
			if( e.f_type==Diamond )
				new en.Item(e.cx, e.cy, e.f_type);
		}
	}

	public function attachLightEntities() {
		for( e in level.l_Entities.all_Torch )
			new en.Torch(e);

		for( e in level.l_Entities.all_Mob )
			new en.Mob(e);

		for( e in level.l_Entities.all_Item )
			switch e.f_type {
				case Diamond:
					var found = false;
					for(ee in en.Item.ALL)
						if( ee.origin!=null && ee.origin.cx==e.cx && ee.origin.cy==e.cy ) {
							found = true;
							break;
						}
					if( !found )
						new en.Item(e.cx, e.cy, DiamondDup);

				case _: new en.Item(e.cx, e.cy, e.f_type);
			}
	}

	override function onDispose() {
		super.onDispose();

		level = null;
		marks = null;

		front.remove();
		customs.remove();
	}

	/**
		Mark the level for re-render at the end of current frame (before display)
	**/
	public inline function invalidate() {
		invalidated = true;
	}

	/**
		Return TRUE if given coordinates are in level bounds
	**/
	public inline function isValid(cx,cy) return cx>=0 && cx<cWid && cy>=0 && cy<cHei;

	/**
		Transform coordinates into a coordId
	**/
	public inline function coordId(cx,cy) return cx + cy*cWid;


	/** Return TRUE if mark is present at coordinates **/
	public inline function hasMark(mark:LevelMark, cx:Int, cy:Int) {
		return !isValid(cx,cy) || !marks.exists(mark) ? false : marks.get(mark).exists( coordId(cx,cy) );
	}

	/** Enable mark at coordinates **/
	public function setMark(cx:Int, cy:Int, mark:LevelMark) {
		if( isValid(cx,cy) && !hasMark(mark,cx,cy) ) {
			if( !marks.exists(mark) )
				marks.set(mark, new Map());
			marks.get(mark).set( coordId(cx,cy), true );
		}
	}

	public inline function setMarks(cx,cy,marks:Array<LevelMark>) {
		for(m in marks)
			setMark(cx,cy,m);
	}

	/** Remove mark at coordinates **/
	public function removeMark(mark:LevelMark, cx:Int, cy:Int) {
		if( isValid(cx,cy) && hasMark(mark,cx,cy) )
			marks.get(mark).remove( coordId(cx,cy) );
	}

	/** Return TRUE if "Collisions" layer contains a collision value **/
	public inline function hasCollision(cx,cy) : Bool {
		return !isValid(cx,cy) ? true : level.l_Collisions.getInt(cx,cy)==1 || extraCollMap.exists(coordId(cx,cy));
	}

	/** Return TRUE if "Collisions" layer contains a collision value **/
	public inline function hasSky(cx,cy) : Bool {
		return !isValid(cx,cy) ? false : level.l_Collisions.getInt(cx,cy)==3;
	}

	public function setExtraCollision(cx,cy,v:Bool) {
		if( isValid(cx,cy) )
			if( v )
				extraCollMap.set( coordId(cx,cy), true );
			else
				extraCollMap.remove( coordId(cx,cy) );
	}

	/** Return TRUE if "Collisions" layer contains a collision value **/
	public inline function hasLadder(cx,cy) : Bool {
		return !isValid(cx,cy) ? true : level.l_Collisions.getInt(cx,cy)==2 || hasCollision(cx,cy) && level.l_Collisions.getInt(cx,cy+1)==2;
	}

	public function setDark(v:Bool) {
		haloMask.setScale(0.1);
		haloMask.visible = v;
		if( v )
			lightWrapper.filter = new h2d.filter.Mask(haloMask);
		else
			lightWrapper.filter = null;

		front.colorMatrix = v ? C.getColorizeMatrixH2d(Const.DARK_LIGHT_COLOR) : null;
		front.alpha = v ? 0.15 : 1;
	}

	/** Render current level**/
	function render() {
		bg.clear();
		walls.clear();
		dark.clear();
		details.clear();
		front.clear();
		customs.clear();

		// Custom tiles
		for(e in level.l_Entities.all_CustomTile) {
			if( e.f_tileId==null || !Assets.tiles.exists(e.f_tileId) ) {
				trace("WARNING: unknown customTile: "+e.f_tileId);
				continue;
			}
			customs.add(
				e.pixelX, e.pixelY,
				Assets.tiles.getTile(e.f_tileId,0, e.f_pivotX, e.f_pivotY)
			);
		}


		// Entrance gate
		var e = level.l_Entities.all_Hero[0];
		if( !hasSky(e.cx,e.cy) && !hasSky(e.cx,e.cy-1) ) {
			var t = Assets.tiles.getTile("stair");
			t.setCenterRatio(0.5,1);
			details.add( e.pixelX, e.pixelY, t );
		}

		// Front
		for( autoTile in level.l_Front_elements.autoTiles ) {
			var tile = level.l_Front_elements.tileset.getAutoLayerTile(autoTile);
			front.add(autoTile.renderX, autoTile.renderY, tile);
		}

		// Bg
		for( autoTile in level.l_Bg.autoTiles ) {
			var tile = level.l_Bg.tileset.getAutoLayerTile(autoTile);
			bg.add(autoTile.renderX, autoTile.renderY, tile);
		}

		// Plants
		for( autoTile in level.l_Plants.autoTiles ) {
			var tile = level.l_Plants.tileset.getAutoLayerTile(autoTile);
			tile.setCenterRatio();
			walls.addTransform(
				autoTile.renderX + Const.GRID*0.5 + rnd(0,6,true),
				autoTile.renderY + Const.GRID*0.5 + rnd(0,6,true),
				rnd(1, 1.5, true),
				rnd(1, 1.5, true),
				rnd(0,M.PI),
				tile
			);
		}

		// Walls
		for( autoTile in level.l_Collisions.autoTiles ) {
			var tile = level.l_Collisions.tileset.getAutoLayerTile(autoTile);
			walls.add(autoTile.renderX, autoTile.renderY, tile);
			burn.add(autoTile.renderX, autoTile.renderY, tile);
		}

		// Dark
		for( autoTile in level.l_DarkRender.autoTiles ) {
			var tile = level.l_DarkRender.tileset.getAutoLayerTile(autoTile);
			dark.add(autoTile.renderX, autoTile.renderY, tile);
		}
	}

	function set_fakeLight(v) {
		fakeLight = v;
		bg.alpha = walls.alpha = fakeLight;
		return fakeLight;
	}

	override function postUpdate() {
		super.postUpdate();

		lightWrapper.alpha += ( ( game.dark ? 0.2 : 1 ) - lightWrapper.alpha ) * 0.05;

		var tx = game.hero.centerX + game.hero.dir*5 + Math.cos(ftime*0.05)*2;
		var ty = game.hero.centerY + Math.sin(ftime*0.032)*2;
		haloMask.x += (tx-haloMask.x)*0.2;
		haloMask.y += (ty-haloMask.y)*0.2;

		haloMask.scaleX += (0.3 + Math.cos(ftime*0.03)*0.04 - haloMask.scaleX) * 0.07;
		haloMask.scaleY += (0.3 + Math.sin(ftime*0.04)*0.03 - haloMask.scaleY) * 0.07;

		if( invalidated ) {
			invalidated = false;
			render();
		}

		// Light warning
		if( !game.dark && game.getAutoSwitchS()<=3 ) {
			var a = ( game.getAutoSwitchS()<=1 ? 0.4 : 0.7 ) + 0.12 * Math.sin(ftime*0.25) + rnd(0,0.04);
			fakeLight = a;
		}
		else
			fakeLight = 1;

	}
}