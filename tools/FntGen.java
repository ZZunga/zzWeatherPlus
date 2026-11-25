import java.awt.*;
import java.awt.font.FontRenderContext;
import java.awt.font.GlyphVector;
import java.awt.image.BufferedImage;
import java.io.*;
import java.util.*;
import javax.imageio.ImageIO;

/**
 * AngelCode BMFont generator (text .fnt + single-page PNG) for Connect IQ.
 *
 *   java tools/FntGen.java <ttf> <outDir> <baseName> <chars> <map|-> <px1> [px2 ...]
 *
 *   chars : glyphs to emit, as the characters the app will draw (e.g. " %-./0123456789:afhkmpst")
 *   map   : "-" for none, or comma list "A=F00D,a=F02E,..." -> draw TTF codepoint 0xF00D
 *           but store it under char 'A' (icon fonts).
 *
 * Vertical anchor (same convention as zzCadence/generate-fonts.ps1):
 *   - text fonts : yoffset is relative to the TOP OF THE DIGITS, base = digit cap height.
 *                  drawText(x, y, ...) puts the digit tops exactly at y.
 *   - icon fonts : yoffset is relative to the top of the tallest glyph in the set,
 *                  base = tallest glyph height. drawText(x, y) puts the icon box top at y.
 *
 * Prints one summary line per size:  px adv cap  (adv = digit '0' advance, or widest icon)
 * - paste these into source/Layout.mc tables when you regenerate.
 */
public class FntGen {

    public static void main(String[] args) throws Exception {
        if (args.length < 6) {
            System.err.println("usage: java FntGen.java <ttf> <outDir> <base> <chars> <map|-> <px> [px ...]");
            System.exit(2);
        }
        Font font = Font.createFont(Font.TRUETYPE_FONT, new File(args[0]));
        File outDir = new File(args[1]);
        outDir.mkdirs();
        String base = args[2];
        String chars = args[3];
        Map<Integer, Integer> map = new LinkedHashMap<>();
        if (!args[4].equals("-")) {
            for (String kv : args[4].split(",")) {
                String[] p = kv.split("=");
                map.put((int) p[0].charAt(0), Integer.parseInt(p[1], 16));
            }
        }
        boolean icon = !map.isEmpty();
        for (int a = 5; a < args.length; a++) {
            generate(font, outDir, base, chars, map, icon, Integer.parseInt(args[a].trim()));
        }
    }

    static class G { int code; BufferedImage img; int[] b; int xadv; }

    static void generate(Font baseFont, File outDir, String base, String chars,
                         Map<Integer, Integer> map, boolean icon, int px) throws IOException {
        Font font = baseFont.deriveFont(Font.PLAIN, (float) px);

        BufferedImage probe = new BufferedImage(4, 4, BufferedImage.TYPE_INT_ARGB);
        Graphics2D pg = probe.createGraphics();
        hints(pg);
        pg.setFont(font);
        FontMetrics fm = pg.getFontMetrics();
        int ascent = fm.getAscent();
        FontRenderContext frc = pg.getFontRenderContext();
        pg.dispose();

        int pad = Math.max(4, px / 6);
        int cell = px * 3 + pad * 2;

        java.util.List<G> glyphs = new ArrayList<>();
        for (int i = 0; i < chars.length(); i++) {
            int code = chars.charAt(i);
            int src = map.containsKey(code) ? map.get(code) : code;
            String s = new String(Character.toChars(src));
            GlyphVector gv = font.createGlyphVector(frc, s);
            G g = new G();
            g.code = code;
            g.xadv = Math.round((float) gv.getGlyphMetrics(0).getAdvanceX());
            g.img = new BufferedImage(cell, cell, BufferedImage.TYPE_INT_ARGB);
            Graphics2D gg = g.img.createGraphics();
            hints(gg);
            gg.setFont(font);
            gg.setColor(Color.WHITE);
            gg.drawString(s, pad, pad + ascent);
            gg.dispose();
            g.b = tight(g.img);
            glyphs.add(g);
        }

        // vertical reference
        int top = Integer.MAX_VALUE, bottom = -1;
        for (G g : glyphs) {
            if (g.b == null) continue;
            boolean ref = icon || (g.code >= '0' && g.code <= '9');
            if (!ref) continue;
            top = Math.min(top, g.b[1]);
            bottom = Math.max(bottom, g.b[3]);
        }
        int cap = bottom - top + 1;
        int lineHeight = cap + Math.round(px * 0.12f);

        // icon fonts: make advance = ink width + small gap so icons pack tightly
        int advRef = 0;
        for (G g : glyphs) {
            if (icon && g.b != null) {
                g.xadv = (g.b[2] - g.b[0] + 1) + Math.max(1, px / 16);
            }
            if (icon) advRef = Math.max(advRef, g.xadv);
            else if (g.code == '0') advRef = g.xadv;
        }

        // pack
        int maxW = 1024, gap = 1, penX = 0, penY = 0, rowH = 0, sheetW = 1;
        int[][] pos = new int[glyphs.size()][2];
        for (int i = 0; i < glyphs.size(); i++) {
            G g = glyphs.get(i);
            int w = g.b == null ? 0 : g.b[2] - g.b[0] + 1;
            int h = g.b == null ? 0 : g.b[3] - g.b[1] + 1;
            if (penX + w > maxW) { penX = 0; penY += rowH + gap; rowH = 0; }
            pos[i][0] = penX; pos[i][1] = penY;
            penX += w + gap;
            rowH = Math.max(rowH, h);
            sheetW = Math.max(sheetW, penX);
        }
        int sheetH = Math.max(1, penY + rowH);

        BufferedImage sheet = new BufferedImage(sheetW, sheetH, BufferedImage.TYPE_INT_ARGB);
        Graphics2D sg = sheet.createGraphics();
        StringBuilder lines = new StringBuilder();
        for (int i = 0; i < glyphs.size(); i++) {
            G g = glyphs.get(i);
            int w = 0, h = 0, xo = 0, yo = 0;
            if (g.b != null) {
                w = g.b[2] - g.b[0] + 1;
                h = g.b[3] - g.b[1] + 1;
                // BMFont 과 같은 형식: R=G=B=A=커버리지(회색조). 흰색+알파만 쓰면 CIQ 가
                // RGB 를 커버리지로 읽어 가장자리가 꽉 찬 흰색이 되어 계단처럼 깨진다.
                for (int yy = 0; yy < h; yy++) {
                    for (int xx = 0; xx < w; xx++) {
                        int a = (g.img.getRGB(g.b[0] + xx, g.b[1] + yy) >>> 24) & 0xFF;
                        sheet.setRGB(pos[i][0] + xx, pos[i][1] + yy, (a << 24) | (a << 16) | (a << 8) | a);
                    }
                }
                xo = icon ? 0 : g.b[0] - pad;
                yo = g.b[1] - top;
            }
            lines.append(String.format(
                "char id=%-3d x=%-4d y=%-4d width=%-4d height=%-4d xoffset=%-4d yoffset=%-4d xadvance=%-4d page=0 chnl=15%n",
                g.code, pos[i][0], pos[i][1], w, h, xo, yo, g.xadv));
        }
        sg.dispose();

        String png = base + "-" + px + "_0.png";
        String fnt = base + "-" + px + ".fnt";
        ImageIO.write(sheet, "png", new File(outDir, png));
        try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, fnt)))) {
            pw.printf("info face=\"%s\" size=%d bold=0 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=1 aa=2 padding=0,0,0,0 spacing=1,1 outline=0%n",
                font.getFamily(), -px);
            pw.printf("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0%n",
                lineHeight, cap, sheetW, sheetH);
            pw.printf("page id=0 file=\"%s\"%n", png);
            pw.printf("chars count=%d%n", glyphs.size());
            pw.print(lines);
        }
        System.out.printf("%s %d %d %d   (%dx%d)%n", base, px, advRef, cap, sheetW, sheetH);
    }

    static void hints(Graphics2D g) {
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
    }

    static int[] tight(BufferedImage img) {
        int w = img.getWidth(), h = img.getHeight();
        int minX = w, minY = h, maxX = -1, maxY = -1;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (((img.getRGB(x, y) >>> 24) & 0xFF) > 8) {
                    if (x < minX) minX = x;
                    if (y < minY) minY = y;
                    if (x > maxX) maxX = x;
                    if (y > maxY) maxY = y;
                }
        return maxX < 0 ? null : new int[]{minX, minY, maxX, maxY};
    }
}
