//
//  CustomView257.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView257: View {
    @State public var text144Text: String = "Followers"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text144Text)
                            .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 81, height: 20, alignment: .topLeading)
    }
}

struct CustomView257_Previews: PreviewProvider {
    static var previews: some View {
        CustomView257()
    }
}
