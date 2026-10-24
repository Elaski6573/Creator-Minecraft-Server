const TILL_RECIPES = {
    // 1. Farmer's Delight - 기름진 흙
    'farmersdelight:rich_soil': {
        result: 'farmersdelight:rich_soil_farmland[moisture=7]',
        sound: 'minecraft:item.hoe.till'
    },
    // 2. Supplementaries - 자갈
    'minecraft:gravel': {
        result: 'supplementaries:raked_gravel',
        sound: 'minecraft:block.gravel.place'
    }
};

BlockEvents.rightClicked(event => {
    const { player, item, block, level } = event;

    // 1. 넵투늄 괭이 확인
    if (!item || item.id !== 'aquaculture:neptunium_hoe') return;
    if(!block) return;
    
    const recipe = TILL_RECIPES[block.id];
    if(!recipe) return;

    // 2. 윗 공간이 공기인지 확인
    const aboveBlock = level.getBlock(block.x, block.y + 1, block.z);
    if (!aboveBlock.id.endsWith('air')) return;

    const srv = event.server || player.server || level.server;

    if (srv) {
        srv.runCommandSilent(`setblock ${block.x} ${block.y} ${block.z} ${recipe.result} replace`);
    } else {
        block.set(recipe.result);
    }

    level.playSound(null, block.x, block.y, block.z, recipe.sound, 'blocks', 1.0, 1.0);

    // 4. 서바이벌 모드일 경우 내구도 소모 및 파괴 처리
    if (!player.isCreative()) {
        item.damageValue += 1;
        if (item.damageValue >= item.maxDamage) {
            level.playSound(null, block.x, block.y, block.z, 'minecraft:entity.item.break', 'players', 1.0, 1.0);
            item.shrink(1);
        }
    }

    player.swing(event.hand || 'main_hand', true);

    // 5. 모든 변환이 끝난 후 이벤트를 취소하여 Aquaculture 모드의 기본 경작 로직 차단
    event.cancel();
});
