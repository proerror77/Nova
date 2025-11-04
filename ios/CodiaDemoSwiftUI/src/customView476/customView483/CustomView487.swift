//
//  CustomView487.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView487: View {
    @State public var text241Text: String = "miss you"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 0.40))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .frame(width: 116, height: 46)
                HStack {
                    Spacer()
                        Text(text241Text)
                            .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 12.522)
        }
        .frame(width: 116, height: 46, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

struct CustomView487_Previews: PreviewProvider {
    static var previews: some View {
        CustomView487()
    }
}
