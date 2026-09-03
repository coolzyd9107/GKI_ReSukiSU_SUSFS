// SPDX-License-Identifier: GPL-2.0
/*
 * hmbird_patch - 将 OPLUS HMBird 内核类型从 HMBIRD_OGKI 强制改为 HMBIRD_GKI
 *
 * OPLUS 的 HMBird 框架通过设备树节点 /soc/oplus,hmbird/version_type
 * 中的 "type" 属性判断内核类型。OGKI = 官方 GKI，GKI = 自定义 GKI。
 * 本补丁在启动早期将其改写，使系统不对自定义内核施加限制。
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>

#define HMBIRD_NODE_PATH "/soc/oplus,hmbird/version_type"
#define HMBIRD_PROP_NAME "type"
#define HMBIRD_OGKI      "HMBIRD_OGKI"
#define HMBIRD_GKI       "HMBIRD_GKI"

static int __init hmbird_patch_init(void)
{
	struct device_node *np;
	struct property *new_prop;
	const char *type;
	int ret;

	np = of_find_node_by_path(HMBIRD_NODE_PATH);
	if (!np)
		return 0;

	/* 读取当前值，不是 OGKI 则跳过 */
	ret = of_property_read_string(np, HMBIRD_PROP_NAME, &type);
	if (ret || strcmp(type, HMBIRD_OGKI))
		goto out;

	/* 构造新属性（kzalloc 确保所有字段零初始化） */
	new_prop = kzalloc(sizeof(*new_prop), GFP_KERNEL);
	if (!new_prop)
		goto out;

	new_prop->name = kstrdup(HMBIRD_PROP_NAME, GFP_KERNEL);
	new_prop->value = kstrdup(HMBIRD_GKI, GFP_KERNEL);
	new_prop->length = strlen(HMBIRD_GKI) + 1;

	if (!new_prop->name || !new_prop->value)
		goto free_prop;

	/* of_update_property 原子替换，比 remove + add 更安全 */
	ret = of_update_property(np, new_prop);
	if (ret) {
		pr_info("hmbird_patch: of_update_property failed (%d)\n", ret);
		goto free_prop;
	}

	pr_info("hmbird_patch: patched %s -> %s\n", HMBIRD_OGKI, HMBIRD_GKI);
	of_node_put(np);
	return 0;

free_prop:
	kfree(new_prop->value);
	kfree(new_prop->name);
	kfree(new_prop);
out:
	of_node_put(np);
	return 0;
}
early_initcall(hmbird_patch_init);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("reigadegr");
MODULE_DESCRIPTION("Forcefully convert HMBIRD_OGKI to HMBIRD_GKI.");
