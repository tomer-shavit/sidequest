#!/usr/bin/env python3
"""Quest card generator — pixel-perfect ASCII frames for any text length."""

import sys
import unicodedata


def display_width(s):
    """Calculate terminal display width accounting for wide chars."""
    return sum(2 if unicodedata.east_asian_width(c) in ('F', 'W') else 1 for c in s)


def pad(text, width):
    """Pad text to exact display width with spaces."""
    return text + ' ' * (width - display_width(text))


def wrap_text(text, max_width):
    """Wrap text to fit within max_width, splitting on spaces."""
    words = text.split()
    lines = []
    current = ''
    for word in words:
        test = (current + ' ' + word).strip()
        if display_width(test) <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def scroll(title, reward=None, content_width=28):
    """Parchment Scroll — original design, meant to be rendered in a code block."""
    cw = content_width
    lines = wrap_text(title, cw - 4)

    reward_str = ''
    if reward:
        reward_str = f'+{reward:,}g'

    out = []
    out.append('   ' + '_' * (cw + 2))
    out.append(' / \\' + ' ' * (cw + 1) + '\\.')
    out.append('|   |' + pad('       Side Quest', cw) + '|.')
    out.append(' \\_ |' + ' ' * cw + '|.')
    for line in lines:
        out.append('    |' + pad('   ' + line, cw) + '|.')
    if reward_str:
        rw = display_width(reward_str)
        out.append('    |' + ' ' * (cw - rw - 1) + reward_str + ' |.')
    out.append('    |' + ' ' * cw + '|.')
    out.append('    |' + pad('   > 1 Open    > 2 Save', cw) + '|.')
    out.append('    |' + pad('   > 0 Skip', cw) + '|.')
    out.append('    |   ' + '_' * (cw - 3) + '|___')
    out.append('    |  /' + ' ' * cw + '/.')
    out.append('    \\_/' + '_' * cw + '/.')
    return '\n'.join(out)


def celtic(title, content_width=28):
    """Option B: Celtic Knot Border"""
    cw = content_width
    lines = wrap_text(title, cw - 4)

    out = []
    out.append('╔╦' + '═' * cw + '╦╗')
    out.append('╠╬' + pad('  SIDE QUEST', cw) + '╬╣')
    out.append('╠╬' + ' ' * cw + '╬╣')
    for line in lines:
        out.append('╠╬' + pad('  ' + line, cw) + '╬╣')
    out.append('╠╬' + ' ' * cw + '╬╣')
    out.append('╠╬' + pad('  > 1 Open    > 2 Save', cw) + '╬╣')
    out.append('╠╬' + pad('  > 0 Skip', cw) + '╬╣')
    out.append('╚╩' + '═' * cw + '╩╝')
    return '\n'.join(out)


def tavern(title, content_width=30):
    """Option C: Tavern Notice Board"""
    cw = content_width
    lines = wrap_text(title, cw - 4)

    header_text = ' SIDE QUEST '
    remaining = cw - len(header_text)
    left_fill = remaining // 2
    right_fill = remaining - left_fill

    out = []
    out.append('┌' + '─' * cw + '┐')
    out.append('│' + '▓' * left_fill + header_text + '▓' * right_fill + '│')
    out.append('├' + '─' * cw + '┤')
    for line in lines:
        out.append('│' + pad('  ' + line, cw) + '│')
    out.append('│' + ' ' * cw + '│')
    out.append('│' + pad('  > 1 Open      > 2 Save', cw) + '│')
    out.append('│' + pad('  > 0 Skip', cw) + '│')
    out.append('└' + '─' * cw + '┘')
    return '\n'.join(out)


def rarity(title, tier='RARE', content_width=30):
    """Option D: Rarity Tier"""
    cw = content_width
    lines = wrap_text(title, cw - 4)

    tier_text = f'  SIDE QUEST  ·  ** {tier} **'

    out = []
    out.append('┏' + '━' * cw + '┓')
    out.append('┃' + pad(tier_text, cw) + '┃')
    out.append('┣' + '━' * cw + '┫')
    for line in lines:
        out.append('┃' + pad('  ' + line, cw) + '┃')
    out.append('┃' + ' ' * cw + '┃')
    out.append('┃' + pad('  > 1 Open      > 2 Save', cw) + '┃')
    out.append('┃' + pad('  > 0 Skip', cw) + '┃')
    out.append('┗' + '━' * cw + '┛')
    return '\n'.join(out)


def minimal(title, content_width=30):
    """Option E: Minimal RPG"""
    cw = content_width
    lines = wrap_text(title, cw - 4)

    header = '── SIDE QUEST '
    remaining = cw - display_width(header)
    header += '─' * remaining

    out = []
    out.append('╭' + header + '╮')
    for line in lines:
        out.append('│' + pad('  ' + line, cw) + '│')
    out.append('│' + ' ' * cw + '│')
    out.append('│' + pad('  > 1 Open      > 2 Save', cw) + '│')
    out.append('│' + pad('  > 0 Skip', cw) + '│')
    out.append('╰' + '─' * cw + '╯')
    return '\n'.join(out)


DESIGNS = {
    'scroll': scroll,
    'celtic': celtic,
    'tavern': tavern,
    'rarity': rarity,
    'minimal': minimal,
}


def verify(card):
    """Verify all lines have same display width."""
    lines = card.split('\n')
    widths = [display_width(l) for l in lines]
    # Scroll has intentionally wider bottom lines
    ok = True
    for i, (w, l) in enumerate(zip(widths, lines)):
        marker = '  '
        if i > 0 and w != widths[1] and not ('___' in l or '/.' in l):
            marker = '!!'
            ok = False
        print(f'  {marker} w={w:3d} | {l}')
    return ok


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate quest card')
    parser.add_argument('title', nargs='?', help='Quest title text')
    parser.add_argument('--reward', type=int, help='Gold reward amount')
    parser.add_argument('--design', default='scroll', choices=DESIGNS.keys())
    parser.add_argument('--sponsor', help='Sponsor name')
    parser.add_argument('--tagline', help='Sponsor tagline')
    parser.add_argument('--json', action='store_true', help='Output full hook JSON')

    parser.add_argument('--test', action='store_true', help='Run test suite')
    args = parser.parse_args()

    if args.test:
        test_titles = [
            'Speed Up Your PostgreSQL Queries',
            'Ship Faster with Better CI/CD',
            'Eggventure Park — Fun for the Whole Dozen',
            'Test Your APIs in Seconds',
            'See Everything in Your Logs',
            'A',
        ]
        for name, fn in DESIGNS.items():
            print(f'\n{"="*50}')
            print(f'  {name.upper()}')
            print(f'{"="*50}')
            for title in test_titles:
                print(f'\n  Title: "{title}"')
                if name == 'rarity':
                    card = fn(title, tier='RARE')
                else:
                    card = fn(title)
                ok = verify(card)
                if not ok:
                    print('  ⚠ ALIGNMENT ERROR!')
                print()
    elif args.title:
        fn = DESIGNS[args.design]
        if args.design == 'scroll':
            card = fn(args.title, reward=args.reward)
        elif args.design == 'rarity':
            card = fn(args.title, tier='RARE')
        else:
            card = fn(args.title)

        if args.json:
            import json
            reward_info = f' +{args.reward:,}g' if args.reward else ''
            reason = f"SideQuest: {args.title}{reward_info}."
            if args.sponsor:
                reason += f" | {args.sponsor}"
                if args.tagline:
                    reason += f" — {args.tagline}"
            print(json.dumps({"decision": "block", "reason": reason}))
        else:
            print(card)
    else:
        parser.print_help()
